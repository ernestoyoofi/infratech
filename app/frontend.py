import os
import requests
import logging
from datetime import datetime
from flask import Flask, render_template, jsonify

app = Flask(__name__, template_folder='templates')

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# BUG: PORT default is 5000 — should be 3000 (Dockerfile EXPOSE is 3000)
API_URL = os.getenv('API_URL', 'http://localhost:8080')
PORT = int(os.getenv('PORT', '5000'))
GRAFANA_URL = os.getenv('GRAFANA_URL', 'http://localhost:3000')
CLOUDWATCH_REGION = os.getenv('CLOUDWATCH_REGION', 'us-east-1')


@app.route('/', methods=['GET'])
def index():
    # BUG: grafana_url not passed to template
    return render_template('index.html', api_url=API_URL)


@app.route('/api/grafana-status', methods=['GET'])
def grafana_status():
    """Check Grafana ECS status"""
    try:
        import boto3
        ecs = boto3.client('ecs', region_name=CLOUDWATCH_REGION)
        response = ecs.describe_services(
            cluster='cloudtech-monitoring-cluster',
            services=['cloudtech-grafana-service']
        )
        if response['services'] and response['services'][0]['runningCount'] > 0:
            return jsonify({'status': 'ok'}), 200
        return jsonify({'status': 'error'}), 500
    except Exception as e:
        logger.warning(f"Grafana check (assuming running): {e}")
        return jsonify({'status': 'ok', 'note': 'fallback'}), 200


@app.route('/api/status', methods=['GET'])
def status():
    return jsonify({
        'frontend': 'online',
        'api_url': API_URL,
        'grafana_url': GRAFANA_URL,
        'cloudwatch_region': CLOUDWATCH_REGION,
        'timestamp': datetime.utcnow().isoformat()
    }), 200


@app.errorhandler(404)
def not_found(error):
    return jsonify({'error': 'Not found'}), 404


@app.errorhandler(500)
def server_error(error):
    return jsonify({'error': 'Internal server error'}), 500


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=PORT, debug=False)
