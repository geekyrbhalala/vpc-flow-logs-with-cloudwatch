import boto3
import json
import os

ec2 = boto3.client('ec2')

SECURITY_GROUP_ID = os.environ['SECURITY_GROUP_ID']  # Inject via Lambda env var
PORT              = int(os.environ.get('PORT', '22'))  # Default to port 22 (SSH)
PROTOCOL          = 'tcp'

def lambda_handler(event, context):
    print("Received event:", json.dumps(event))

#     # Get the attacker's IP address from the event (you’ll need to customize this part)
#     attacker_ip = extract_ip_from_event(event)
#     if not attacker_ip:
#         print("No IP found to block.")
#         return

#     cidr_ip = f"{attacker_ip}/32"
    
#     try:
#         # Check if the rule already exists
#         response = ec2.describe_security_group_rules(
#             Filters=[
#                 {"Name": "group-id", "Values": [SECURITY_GROUP_ID]},
#                 {"Name": "cidr", "Values": [cidr_ip]},
#                 {"Name": "from-port", "Values": [str(PORT)]},
#                 {"Name": "ip-protocol", "Values": [PROTOCOL]},
#             ]
#         )
#         rules = response.get('SecurityGroupRules', [])

#         if rules:
#             print(f"IP {cidr_ip} already blocked.")
#         else:
#             # Block the IP
#             ec2.authorize_security_group_ingress(
#                 GroupId=SECURITY_GROUP_ID,
#                 IpPermissions=[
#                     {
#                         'IpProtocol': PROTOCOL,
#                         'FromPort': PORT,
#                         'ToPort': PORT,
#                         'IpRanges': [{'CidrIp': cidr_ip, 'Description': 'Blocked by Lambda'}]
#                     }
#                 ]
#             )
#             print(f"Blocked IP: {cidr_ip}")

#     except Exception as e:
#         print(f"Error blocking IP: {str(e)}")
#         raise e

# def extract_ip_from_event(event):
#     # Example: Extract IP from a CloudWatch alarm via SNS message
#     try:
#         message = json.loads(event['Records'][0]['Sns']['Message'])
#         attacker_ip = message.get('Trigger', {}).get('Dimensions', [])[0].get('value')
#         return attacker_ip
#     except Exception as e:
#         print(f"Failed to extract IP: {str(e)}")
#         return None
