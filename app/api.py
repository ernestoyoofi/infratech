import os
import json
import logging
from datetime import datetime
from functools import wraps

import boto3
import psycopg2
import redis
from flask import Flask, request, jsonify
from prometheus_client import Counter, Histogram, start_http_server
import time

# Initialize Flask app
app = Flask(__name__)

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment variables
DB_HOST = os.getenv('DB_HOST', 'localhost')
DB_PORT = int(os.getenv('DB_PORT', '5432'))
DB_NAME = os.getenv('DB_NAME', 'lksdb')
DB_USER = os.getenv('DB_USER', 'postgres')
DB_PASSWORD = os.getenv('DB_PASSWORD', 'postgres')

REDIS_HOST = os.getenv('REDIS_HOST', 'localhost')
REDIS_PORT = int(os.getenv('REDIS_PORT', '6379'))

KINESIS_STREAM = os.getenv('KINESIS_STREAM', 'cloudtech-event-stream')
AWS_REGION = os.getenv('AWS_REGION', 'us-east-1')

# Initialize AWS clients
kinesis_client = boto3.client('kinesis', region_name=AWS_REGION)

# Initialize Redis
try:
    redis_client = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)
    redis_client.ping()
except Exception as e:
    logger.warning(f"Redis connection failed: {e}")
    redis_client = None

# Prometheus metrics
request_count = Counter('api_requests_total', 'Total API requests', ['method', 'endpoint', 'status'])
request_duration = Histogram('api_request_duration_seconds', 'API request duration', ['method', 'endpoint'])
users_created = Counter('users_created_total', 'Total users created')
users_deleted = Counter('users_deleted_total', 'Total users deleted')

# Database connection pool
def get_db():
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD
        )
        return conn
    except Exception as e:
        logger.error(f"Database connection error: {e}")
        raise

# Initialize database
def init_db():
    conn = get_db()
    cur = conn.cursor()
    
    cur.execute('''
        CREATE TABLE IF NOT EXISTS users (
            id SERIAL PRIMARY KEY,
            name VARCHAR(255) NOT NULL,
            email VARCHAR(255) NOT NULL,
            phone VARCHAR(20),
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            tenant_id VARCHAR(50) NOT NULL
        )
    ''')
    
    cur.execute('''
        CREATE TABLE IF NOT EXISTS audit_logs (
            id SERIAL PRIMARY KEY,
            action VARCHAR(50),
            user_id INTEGER,
            user_email VARCHAR(255),
            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            details JSONB,
            tenant_id VARCHAR(50)
        )
    ''')
    
    conn.commit()
    cur.close()
    conn.close()

# Publish event to Kinesis
def publish_event(action, user_data, tenant_id):
    try:
        event = {
            'action': action,
            'user_data': user_data,
            'tenant_id': tenant_id,
            'timestamp': datetime.utcnow().isoformat()
        }
        
        kinesis_client.put_record(
            StreamName=KINESIS_STREAM,
            Data=json.dumps(event),
            PartitionKey=tenant_id
        )
        logger.info(f"Event published: {action} for tenant {tenant_id}")
    except Exception as e:
        logger.error(f"Failed to publish event: {e}")

# Request tracking decorator
def track_request(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        start_time = time.time()
        try:
            result = f(*args, **kwargs)
            status = result[1] if isinstance(result, tuple) else 200
            request_count.labels(
                method=request.method,
                endpoint=request.path,
                status=status
            ).inc()
            return result
        finally:
            duration = time.time() - start_time
            request_duration.labels(
                method=request.method,
                endpoint=request.path
            ).observe(duration)
    
    return decorated_function

# Routes
@app.route('/api/health', methods=['GET'])
@track_request
def health():
    """Health check endpoint"""
    try:
        conn = get_db()
        conn.close()
        db_status = 'connected'
    except:
        db_status = 'disconnected'
    
    redis_status = 'connected' if redis_client and redis_client.ping() else 'disconnected'
    
    return jsonify({
        'status': 'healthy',
        'database': db_status,
        'redis': redis_status,
        'timestamp': datetime.utcnow().isoformat()
    }), 200

@app.route('/api/users', methods=['GET'])
@track_request
def list_users():
    """List all users for current tenant"""
    tenant_id = request.headers.get('X-Tenant-ID', 'default')
    search = request.args.get('search', '')
    
    try:
        conn = get_db()
        cur = conn.cursor()
        
        if search:
            query = f"SELECT id, name, email, phone, created_at FROM users WHERE tenant_id = '{tenant_id}' AND name LIKE '%{search}%' ORDER BY created_at DESC"
            cur.execute(query)
        else:
            cur.execute('SELECT id, name, email, phone, created_at FROM users WHERE tenant_id = %s ORDER BY created_at DESC', (tenant_id,))
        
        users = cur.fetchall()
        
        user_list = [
            {
                'id': u[0],
                'name': u[1],
                'email': u[2],
                'phone': u[3],
                'created_at': u[4].isoformat() if u[4] else None
            }
            for u in users
        ]
        
        cur.close()
        conn.close()
        
        return jsonify({'users': user_list}), 200
    except Exception as e:
        logger.error(f"Error listing users: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/users', methods=['POST'])
@track_request
def create_user():
    """Create a new user"""
    tenant_id = request.headers.get('X-Tenant-ID', 'default')
    data = request.get_json()
    
    if not data or 'name' not in data or 'email' not in data:
        return jsonify({'error': 'Missing required fields'}), 400
    
    conn = get_db()
    cur = conn.cursor()
    
    cur.execute(
        'INSERT INTO users (name, email, phone, tenant_id) VALUES (%s, %s, %s, %s) RETURNING id',
        (data['name'], data['email'], data.get('phone'), tenant_id)
    )
    user_id = cur.fetchone()[0]
    
    user_data = {
        'id': user_id,
        'name': data['name'],
        'email': data['email'],
        'phone': data.get('phone')
    }
    
    publish_event('user.created', user_data, tenant_id)
    users_created.inc()
    
    cur.close()
    conn.close()
    
    return jsonify({'id': user_id, **user_data}), 201

@app.route('/api/users/<int:user_id>', methods=['GET'])
@track_request
def get_user(user_id):
    """Get a specific user"""
    tenant_id = request.headers.get('X-Tenant-ID', 'default')
    
    try:
        conn = get_db()
        cur = conn.cursor()
        
        cur.execute(
            'SELECT id, name, email, phone, created_at, updated_at FROM users WHERE id = %s AND tenant_id = %s',
            (user_id, tenant_id)
        )
        user = cur.fetchone()
        
        cur.close()
        conn.close()
        
        if not user:
            return jsonify({'error': 'User not found'}), 404
        
        return jsonify({
            'id': user[0],
            'name': user[1],
            'email': user[2],
            'phone': user[3],
            'created_at': user[4].isoformat() if user[4] else None,
            'updated_at': user[5].isoformat() if user[5] else None
        }), 200
    except Exception as e:
        logger.error(f"Error getting user: {e}")
        return jsonify({'error': str(e)}), 500

@app.route('/api/users/<int:user_id>', methods=['PUT'])
@track_request
def update_user(user_id):
    """Update a user"""
    tenant_id = request.headers.get('X-Tenant-ID', 'default')
    data = request.get_json()
    
    conn = get_db()
    cur = conn.cursor()
    
    cur.execute('SELECT id FROM users WHERE id = %s AND tenant_id = %s', (user_id, tenant_id))
    if not cur.fetchone():
        return jsonify({'error': 'User not found'}), 404
    
    updates = []
    values = []
    if 'name' in data:
        updates.append('name = %s')
        values.append(data['name'])
    if 'email' in data:
        updates.append('email = %s')
        values.append(data['email'])
    if 'phone' in data:
        updates.append('phone = %s')
        values.append(data['phone'])
    
    if not updates:
        return jsonify({'error': 'No fields to update'}), 400
    
    updates.append('updated_at = CURRENT_TIMESTAMP')
    values.append(user_id)
    values.append(tenant_id)
    
    query = f"UPDATE users SET {', '.join(updates)} WHERE id = %s AND tenant_id = %s"
    cur.execute(query, values)
    
    publish_event('user.updated', {'id': user_id, **data}, tenant_id)
    
    cur.close()
    conn.close()
    
    return jsonify({'id': user_id, **data}), 200

@app.route('/api/users/<int:user_id>', methods=['DELETE'])
@track_request
def delete_user(user_id):
    """Delete a user"""
    tenant_id = request.headers.get('X-Tenant-ID', 'default')
    
    conn = get_db()
    cur = conn.cursor()
    
    cur.execute('SELECT name, email FROM users WHERE id = %s AND tenant_id = %s', (user_id, tenant_id))
    user = cur.fetchone()
    if not user:
        return jsonify({'error': 'User not found'}), 404
    
    cur.execute('DELETE FROM users WHERE id = %s AND tenant_id = %s', (user_id, tenant_id))
    
    publish_event('user.deleted', {'id': user_id, 'name': user[0], 'email': user[1]}, tenant_id)
    users_deleted.inc()
    
    cur.close()
    conn.close()
    
    return jsonify({'message': 'User deleted'}), 200

@app.route('/api/status', methods=['GET'])
@track_request
def status():
    """System status endpoint"""
    try:
        conn = get_db()
        cur = conn.cursor()
        cur.execute('SELECT COUNT(*) FROM users')
        user_count = cur.fetchone()[0]
        cur.close()
        conn.close()
    except:
        user_count = 0
    
    return jsonify({
        'api': 'online',
        'database': 'connected',
        'kinesis': 'active',
        'user_count': user_count,
        'timestamp': datetime.utcnow().isoformat()
    }), 200

if __name__ == '__main__':
    start_http_server(9100)
    
    try:
        init_db()
    except Exception as e:
        logger.error(f"Database initialization failed: {e}")
    
    app.run(host='0.0.0.0', port=8080, debug=False)
