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
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

# Step 3: Create trust policy file for EBS CSI driver
cat <<EOF > aws-ebs-csi-driver-trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::$AWS_ACCOUNT_ID:oidc-provider/$OIDC_PROVIDER"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "$OIDC_PROVIDER:aud": "sts.amazonaws.com",
          "$OIDC_PROVIDER:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }
  ]
}
EOF

echo "Trust policy created in aws-ebs-csi-driver-trust-policy.json"

# Step 4: Create or update the role
read -p "Enter IAM role name (default: AmazonEKS_EBS_CSI_DriverRole): " ROLE_NAME
ROLE_NAME=${ROLE_NAME:-AmazonEKS_EBS_CSI_DriverRole}

# Check if the role already exists
ROLE_EXISTS=$(aws iam list-roles --query "Roles[?RoleName=='$ROLE_NAME'].RoleName" --output text)
if [ "$ROLE_EXISTS" == "$ROLE_NAME" ]; then
  echo "Role $ROLE_NAME already exists. Deleting the role..."
  
  # Detach any attached policies before deleting the role
  ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name $ROLE_NAME --query "AttachedPolicies[].PolicyArn" --output text)
  for POLICY_ARN in $ATTACHED_POLICIES; do
    aws iam detach-role-policy --role-name $ROLE_NAME --policy-arn $POLICY_ARN
  done

  # Delete the role
  aws iam delete-role --role-name $ROLE_NAME
  
  echo "Role $ROLE_NAME deleted."
fi

# Create the role
aws iam create-role \
  --role-name $ROLE_NAME \
  --assume-role-policy-document file://aws-ebs-csi-driver-trust-policy.json

# Step 5: Attach the policy
aws iam attach-role-policy \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
  --role-name $ROLE_NAME

# Step 6: Create the addon
# Ensure role ARN is correct
ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME --query "Role.Arn" --output text)

aws eks create-addon --cluster-name $CLUSTER --addon-name aws-ebs-csi-driver \
  --service-account-role-arn $ROLE_ARN

if [ $? -ne 0 ]; then
  echo "Failed to create the addon. Please check the IAM role permissions and ensure it is in the same account."
else
  echo "EBS CSI Driver setup complete."
fi
