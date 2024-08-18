#!/bin/bash

# Step 1: Get cluster name
echo "Fetching available EKS clusters..."
CLUSTERS=($(aws eks list-clusters --query "clusters" --output text))
echo "Select a cluster by number:"
for i in "${!CLUSTERS[@]}"; do
  echo "$i) ${CLUSTERS[$i]}"
done

read -p "Enter number: " CLUSTER_NUMBER
CLUSTER=${CLUSTERS[$CLUSTER_NUMBER]}

# Step 2: Get OIDC URL
OIDC_URL=$(aws eks describe-cluster --name $CLUSTER --query "cluster.identity.oidc.issuer" --output text)
OIDC_PROVIDER=${OIDC_URL#https://}

echo "OIDC Provider URL: $OIDC_PROVIDER"

# Step 3: Create the IAM OIDC identity provider
echo "Creating IAM OIDC identity provider..."
aws iam create-open-id-connect-provider \
    --url "https://$OIDC_PROVIDER" \
    --client-id-list sts.amazonaws.com \

if [ $? -eq 0 ]; then
    echo "IAM OIDC identity provider created successfully."
else
    echo "Failed to create IAM OIDC identity provider."
fi
