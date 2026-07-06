import json
import base64
import logging
import os
import boto3
from datetime import datetime

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize AWS clients
eventbridge = boto3.client('events')
dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

# Environment variables
EVENT_BUS_NAME = "lks-saas-events"
AUDIT_TABLE_NAME = os.getenv('AUDIT_TABLE_NAME', 'lks-audit-log')
SNS_TOPIC_ARN = os.getenv('SNS_TOPIC_ARN', 'arn:aws:sns:us-east-1:123456789012:lks-user-events')
AWS_REGION = os.getenv('AWS_REGION', 'us-east-1')


def lambda_handler(event, context):
    """
    Lambda function to process Kinesis events and forward to EventBridge
    """
    
    audit_table = dynamodb.Table(AUDIT_TABLE_NAME)
    
    for record in event['Records']:
        payload = json.loads(base64.b64decode(record['kinesis']['data']))
        
        logger.info(f"Processing event: {payload['action']}")
        
        eventbridge.put_events(
            Entries=[
                {
                    'Source': 'lks.api',
                    'DetailType': payload['action'],
                    'Detail': json.dumps(payload),
                    'EventBusName': EVENT_BUS_NAME
                }
            ]
        )
        
        audit_entry = {
            'id': f"{payload['tenant_id']}#{datetime.utcnow().isoformat()}",
            'action': payload['action'],
            'user_data': payload.get('user_data', {}),
            'tenant_id': payload['tenant_id'],
            'timestamp': datetime.utcnow().isoformat()
        }
        
        audit_table.put_item(Item=audit_entry)
        logger.info(f"Audit log created: {audit_entry['id']}")
        
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=f"User Event: {payload['action']}",
            Message=json.dumps(payload, indent=2)
        )
        
        logger.info(f"Event processed successfully: {payload['action']}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Events processed successfully',
            'recordsProcessed': len(event['Records'])
        })
    }
