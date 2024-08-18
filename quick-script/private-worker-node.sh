#!/bin/bash

# Variables
CLUSTER_NAME="eks"
REGION="us-east-1"
NODE_NAME="eks"
KEY_NAME="devsecops"

# Function to check AWS credentials
check_credentials() {
    aws sts get-caller-identity >> /dev/null
    return $?
}

# Function to check if the nodegroup exists
check_nodegroup_exists() {
    local nodegroup_info
    nodegroup_info=$(eksctl get nodegroup --cluster "$CLUSTER_NAME" --region "$REGION" 2>&1)
    if echo "$nodegroup_info" | grep -q "$NODE_NAME"; then
        return 0
    else
        return 1
    fi
}

# Check AWS credentials before proceeding
if check_credentials; then
    echo "Credentials tested, proceeding with the nodegroup creation."

    # Check if the nodegroup already exists
    if ! check_nodegroup_exists; then
        # Creation of nodegroup
        eksctl create nodegroup \
            --cluster "$CLUSTER_NAME" \
            --name "$NODE_NAME" \
            --nodes 4 \
            --nodes-min 1 \
            --nodes-max 4 \
            --node-type t3.medium \
            --node-volume-size 8 \
            --ssh-access \
            --ssh-public-key "$KEY_NAME" \
            --asg-access \
            --external-dns-access \
            --full-ecr-access \
            --appmesh-access \
            --alb-ingress-access \
            --node-private-networking 

        if [ $? -eq 0 ]; then
            echo "Nodegroup $NODE_NAME created successfully."
        else
            echo "Failed to create nodegroup $NODE_NAME."
            exit 1
        fi
    else
        echo "Nodegroup $NODE_NAME already exists."
    fi
else
    echo "Please run 'aws configure' and set the correct credentials."
    echo "Nodegroup creation failed."
fi

