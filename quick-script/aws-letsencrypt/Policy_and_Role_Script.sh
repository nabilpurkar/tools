#!/bin/bash

# Step 1: List IAM roles matching "eks-nodegroup"
echo "Fetching IAM roles containing 'eks-nodegroup'..."
ROLES=($(aws iam list-roles --query "Roles[*].RoleName" --output text | tr '\t' '\n' | grep -i eks-nodegroup))

if [ ${#ROLES[@]} -eq 0 ]; then
    echo "No roles containing 'eks-nodegroup' were found."
    exit 1
fi

echo "Select a role by number:"
for i in "${!ROLES[@]}"; do
  echo "$i) ${ROLES[$i]}"
done

read -p "Enter number: " ROLE_NUMBER
NODEGROUP_ROLE=${ROLES[$ROLE_NUMBER]}

# Step 2: Create trust policy JSON
cat <<EOF > trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::$(aws sts get-caller-identity --query "Account" --output text):role/$NODEGROUP_ROLE"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

echo "Trust policy created in trust-policy.json"

# Step 3: Create the Route 53 policy JSON
cat <<EOF > route53-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "route53:GetChange",
            "Resource": "arn:aws:route53:::change/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "route53:ChangeResourceRecordSets",
                "route53:ListResourceRecordSets"
            ],
            "Resource": "arn:aws:route53:::hostedzone/*"
        }
    ]
}
EOF

echo "Route 53 policy created in route53-policy.json"

# Step 4: Attach the trust policy to the selected role
echo "Updating trust policy for role $NODEGROUP_ROLE..."
aws iam update-assume-role-policy --role-name $NODEGROUP_ROLE --policy-document file://trust-policy.json

if [ $? -eq 0 ]; then
    echo "Trust policy updated successfully."
else
    echo "Failed to update trust policy."
    exit 1
fi

# Step 5: Attach the Route 53 policy to the selected role
echo "Attaching Route 53 policy to role $NODEGROUP_ROLE..."
aws iam put-role-policy --role-name $NODEGROUP_ROLE --policy-name Route53Policy --policy-document file://route53-policy.json

if [ $? -eq 0 ]; then
    echo "Route 53 policy attached successfully."
else
    echo "Failed to attach Route 53 policy."
    exit 1
fi

echo "Script execution completed successfully."
