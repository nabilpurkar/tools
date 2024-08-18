#!/bin/bash

# Step 1: Download the IAM policy JSON file
curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.7.2/docs/install/iam_policy.json

# Step 2: Create or update the IAM policy
aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://iam_policy.json 2>/dev/null || \
aws iam create-policy-version --policy-arn $(aws iam list-policies --query "Policies[?PolicyName=='AWSLoadBalancerControllerIAMPolicy'].Arn" --output text) --policy-document file://iam_policy.json --set-as-default

# Step 3: Get the EKS cluster name
echo "Fetching EKS clusters in region us-east-1..."
clusters=$(aws eks list-clusters --region us-east-1 --query "clusters" --output text)
echo "Available clusters: $clusters"
read -p "Enter the cluster name or leave blank to auto-select the first one: " user_cluster
CLUSTER_NAME=${user_cluster:-$(echo $clusters | awk '{print $1}')}

# Step 4: Create or update the IAM policy
echo "Creating or updating IAM policy..."
aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://iam_policy.json 2>/dev/null || \
aws iam create-policy-version --policy-arn $(aws iam list-policies --query "Policies[?PolicyName=='AWSLoadBalancerControllerIAMPolicy'].Arn" --output text) --policy-document file://iam_policy.json --set-as-default

# Step 5: Get the policy ARN
echo "Fetching policy ARN..."
AWSLBCPolicy=$(aws iam list-policies --query "Policies[?PolicyName=='AWSLoadBalancerControllerIAMPolicy'].Arn" --output text)

# Step 6: Create the IAM service account
read -p "Enter the role name or leave blank to use default (AmazonEKSLoadBalancerControllerRole): " user_role
ROLE_NAME=${user_role:-AmazonEKSLoadBalancerControllerRole}
eksctl create iamserviceaccount \
  --cluster=$CLUSTER_NAME \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --role-name=$ROLE_NAME \
  --attach-policy-arn=$AWSLBCPolicy \
  --approve

echo "IAM service account creation completed."

