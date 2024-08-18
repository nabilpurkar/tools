#!/bin/bash

# Variables
VPC_ID="vpc-bb06ffdd"
SUBNETS=("subnet-3b5dd937" "subnet-a6c9738b" "subnet-2f4ed54a" "subnet-673e4b2e" "subnet-ebab72d7" "subnet-aba817f0")
CERTIFICATE_ARN="XXXXXXXXX"
LOAD_BALANCER_NAME="my-internal-lb"
LOAD_BALANCER_SCHEME="internal"  # Change to "internet-facing" if needed
TARGET_GROUPS=("nginx:80" "jenkins:8080" "nexus:8081" "sonar:9000")

# Step 1: Create load balancer
echo "Creating load balancer..."
LOAD_BALANCER_ARN=$(aws elbv2 create-load-balancer --name $LOAD_BALANCER_NAME --subnets "${SUBNETS[@]}" --scheme $LOAD_BALANCER_SCHEME --type application --query 'LoadBalancers[0].LoadBalancerArn' --output text)

# Step 2: Create target groups
echo "Creating target groups..."
declare -A TARGET_ARN_MAP
for TG in "${TARGET_GROUPS[@]}"; do
    NAME=$(echo $TG | cut -d: -f1)
    PORT=$(echo $TG | cut -d: -f2)
    TARGET_ARN=$(aws elbv2 create-target-group --name $NAME --protocol HTTP --port $PORT --vpc-id $VPC_ID --query 'TargetGroups[0].TargetGroupArn' --output text)
    TARGET_ARN_MAP[$NAME]=$TARGET_ARN
done

# Step 3: Create HTTP to HTTPS listener with redirection
echo "Creating HTTP to HTTPS listener with redirection..."
aws elbv2 create-listener \
    --load-balancer-arn $LOAD_BALANCER_ARN \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=redirect,RedirectConfig="{Protocol=HTTPS,Port=443,StatusCode=HTTP_301}"

# Step 4: Check if HTTPS listener already exists
EXISTING_HTTPS_LISTENER=$(aws elbv2 describe-listeners --load-balancer-arn $LOAD_BALANCER_ARN --query "Listeners[?Protocol=='HTTPS'].ListenerArn" --output text)

# Step 5: Create HTTPS listener with SSL certificate if it does not already exist
if [ -z "$EXISTING_HTTPS_LISTENER" ]; then
    echo "Creating HTTPS listener with SSL certificate..."
    aws elbv2 create-listener \
        --load-balancer-arn $LOAD_BALANCER_ARN \
        --protocol HTTPS \
        --port 443 \
        --ssl-policy ELBSecurityPolicy-TLS13-1-2-2021-06 \
        --certificates CertificateArn=$CERTIFICATE_ARN \
        --default-actions Type=forward,TargetGroupArn=${TARGET_ARN_MAP["nginx"]}
else
    echo "HTTPS listener already exists."
fi

echo "Script execution completed."
