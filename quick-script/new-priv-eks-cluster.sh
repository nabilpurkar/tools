#!/bin/bash

# Variables
CLUSTER_NAME="eks"
REGION="us-east-1"
NODE_NAME="eks"
KEY_NAME="devsecops"
PRIVATE_SUBNETS="subnet-a6c9738b,subnet-673e4b2e"

# Function to check AWS credentials
check_credentials() {
    aws sts get-caller-identity >> /dev/null
    return $?
}

# Function to check if the cluster exists
check_cluster_exists() {
    local cluster_info
    cluster_info=$(eksctl get cluster --name "$CLUSTER_NAME" --region "$REGION" 2>&1)
    if echo "$cluster_info" | grep -q "Error: unknown cluster \"$CLUSTER_NAME\""; then
        return 1
    else
        return 0
    fi
}

# Function to check if OIDC provider is associated
check_oidc_association() {
    local oidc_info
    oidc_info=$(eksctl utils associate-iam-oidc-provider --region "$REGION" --cluster "$CLUSTER_NAME" --dry-run 2>&1)
    if echo "$oidc_info" | grep -q "Cluster \"$CLUSTER_NAME\" not found"; then
        return 1
    else
        return 0
    fi
}

# Function to check if the cluster exists
check_cluster_exists() {
    local cluster_info
    cluster_info=$(eksctl get cluster "$CLUSTER_NAME" --region "$REGION" 2>&1)
    if echo "$cluster_info" | grep -q "No cluster found for name: $CLUSTER_NAME"; then
        return 1
    elif echo "$cluster_info" | grep -q "$CLUSTER_NAME"; then
        return 0
    else
        return 1
    fi
}



# Check AWS credentials before proceeding
if check_credentials; then
    echo "Credentials tested, proceeding with the cluster creation."

    # Check if the cluster already exists
    if ! check_cluster_exists; then
        # Creation of EKS cluster
        eksctl create cluster \
            --name "$CLUSTER_NAME" \
            --version 1.27 \
            --region "$REGION" \
            --vpc-private-subnets "$PRIVATE_SUBNETS" \
            --without-nodegroup 

        if [ $? -eq 0 ]; then
            echo "EKS Cluster $CLUSTER_NAME created successfully."
        else
            echo "Failed to create EKS Cluster $CLUSTER_NAME."
            exit 1
        fi
    else
        echo "Cluster $CLUSTER_NAME already exists. Skipping cluster creation."
    fi

    # Check if OIDC provider is associated
    if ! check_oidc_association; then
        echo "Associating OIDC provider with the cluster."
        eksctl utils associate-iam-oidc-provider --region "$REGION" --cluster "$CLUSTER_NAME" --approve

        if [ $? -eq 0 ]; then
            echo "OIDC provider associated successfully."
        else
            echo "Failed to associate OIDC provider."
            exit 1
        fi
    else
        echo "OIDC provider is already associated with the cluster."
    fi

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
    echo "Cluster setup failed."
fi
