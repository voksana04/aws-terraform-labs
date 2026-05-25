import json
import urllib.request
import os

def lambda_handler(event, context):
    slack_webhook_url = os.environ.get('SLACK_WEBHOOK_URL')
    
    for record in event['Records']:
        sns_message = record['Sns']['Message']
        subject = record['Sns'].get('Subject', 'AWS CloudWatch Alarm Triggered')
        
        # Структура повідомлення для Slack
        payload = {
            "text": f"🚨 *{subject}* 🚨\n\n*Деталі події:*\n```json\n{sns_message}\n```"
        }
        
        req = urllib.request.Request(
            slack_webhook_url,
            data=json.dumps(payload).encode('utf-8'),
            headers={'Content-Type': 'application/json'},
            method='POST'
        )
        
        try:
            with urllib.request.urlopen(req) as response:
                response.read()
        except Exception as e:
            print(f"Помилка відправки у Slack: {e}")
            
    return {'statusCode': 200, 'body': 'Ok'}