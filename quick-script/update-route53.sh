#!/bin/bash

# Variables
SCRIPT_RUN_PATH="$PWD"
EXPECTED_SCRIPT_NAME="update-route53.sh"
SCRIPT_NAME=$(basename "$0")
HOSTED_ZONE_ID="Z01111111111111"
TTL=300

# Domain names array
DOMAIN_NAMES=(
    "vpn.sre-solutions.tech"
    "jenkins.sre-solutions.tech"
    "jfrog.sre-solutions.tech"
    "harbor.sre-solutions.tech"
    "sonar.sre-solutions.tech"
)

# Check script name
if [[ "$SCRIPT_NAME" != "$EXPECTED_SCRIPT_NAME" ]]; then
    echo "Error: Script name does not match '$EXPECTED_SCRIPT_NAME'. Please rename the script."
    exit 1
fi

# Get public IP
PUBLIC_IP=$(curl -s ifconfig.io)

# Update DNS for each domain
for DOMAIN_NAME in "${DOMAIN_NAMES[@]}"; do
    echo "Updating DNS for $DOMAIN_NAME..."
    
    # Create JSON file for Route 53 update
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

    # Update Route 53 record
    if aws route53 change-resource-record-sets --hosted-zone-id "$HOSTED_ZONE_ID" --change-batch file:///tmp/route53-update.json; then
        echo "✅ Successfully updated $DOMAIN_NAME to $PUBLIC_IP"
    else
        echo "❌ Failed to update $DOMAIN_NAME"
    fi
    
    # Cleanup
    rm /tmp/route53-update.json
done

# Create systemd service
SERVICE_FILE_PATH="/etc/systemd/system/update-route53.service"
if [[ ! -f "$SERVICE_FILE_PATH" ]]; then
    echo "Creating systemd service file..."
    cat > "$SERVICE_FILE_PATH" <<EOF
[Unit]
Description=Update Route 53 DNS records with EC2 public IP
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash $SCRIPT_RUN_PATH/$SCRIPT_NAME
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    # Enable service
    sudo systemctl daemon-reload
    sudo systemctl enable update-route53.service
    echo "Service enabled and will run on startup"
fi
