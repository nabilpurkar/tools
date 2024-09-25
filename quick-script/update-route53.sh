#This script automatically updates a Route 53 DNS A record with the current public IP of an EC2 instance. It checks if the script is correctly named, retrieves the instance's IP, and updates the specified DNS record using the AWS CLI. Additionally, it creates and enables a systemd service to ensure the DNS record is updated automatically on instance startup.

#!/bin/bash

# Variables
SCRIPT_RUN_PATH="$PWD"
EXPECTED_SCRIPT_NAME="update-route53.sh"  # Expected script name
SCRIPT_NAME=$(basename "$0")  # Get the actual running script name
HOSTED_ZONE_ID="HOSTED_ZONE_ID"  # Replace with your Route 53 hosted zone ID
DOMAIN_NAME="DOMAIN_NAME"        # Replace with your DNS name
TTL=300                          # Time to live for the DNS record

# Check if the running script name matches the expected name
if [[ "$SCRIPT_NAME" != "$EXPECTED_SCRIPT_NAME" ]]; then
    echo "Error: Script name does not match '$EXPECTED_SCRIPT_NAME'. Please rename the script or update the expected name in the script."
    exit 1
fi

# Get the instance's public IP
PUBLIC_IP=$(curl -s ifconfig.io)

# Create a JSON file for the Route 53 update
cat > /tmp/route53-update.json <<EOF
{
  "Comment": "Auto updating DNS for EC2 instance",
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "$DOMAIN_NAME",
      "Type": "A",
      "TTL": $TTL,
      "ResourceRecords": [{"Value": "$PUBLIC_IP"}]
    }
  }]
}
EOF

# Update the Route 53 DNS record
aws route53 change-resource-record-sets --hosted-zone-id "$HOSTED_ZONE_ID" --change-batch file:///tmp/route53-update.json

# Cleanup
rm /tmp/route53-update.json

# Check if the service file exists
SERVICE_FILE_PATH="/etc/systemd/system/update-route53.service"
if [[ ! -f "$SERVICE_FILE_PATH" ]]; then
    echo "Creating systemd service file at $SERVICE_FILE_PATH"
    # Create a systemd service file
    cat > "$SERVICE_FILE_PATH" <<EOF
[Unit]
Description=Update Route 53 DNS record with new EC2 public IP on instance start
After=network.target

[Service]
ExecStart=$SCRIPT_RUN_PATH/$SCRIPT_NAME

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and enable the service
    sudo systemctl daemon-reload
    sudo systemctl enable update-route53.service
    echo "Service enabled and will run on startup."
else
    echo "Service file already exists."
fi
