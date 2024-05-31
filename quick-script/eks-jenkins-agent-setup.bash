#!/bin/bash

namespace="default"
action=""

# Parse command-line arguments
while getopts ":n:" opt; do
  case ${opt} in
    n )
      namespace=$OPTARG
      ;;
    \? )
      echo "Usage: $0 [-n namespace]"
      exit 1
      ;;
  esac
done

# Prompt user for action
read -p "Enter 1 to apply or 2 to delete resources: " action

if [ "$action" != "1" ] && [ "$action" != "2" ]; then
  echo "Invalid option."
  exit 1
fi

# Apply or delete resources based on user input
if [ "$action" == "1" ]; then
  # Apply ServiceAccount
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins
  namespace: $namespace
EOF

  # Apply Secret
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: jenkins-secret
  namespace: $namespace
  annotations:
    kubernetes.io/service-account.name: jenkins
type: kubernetes.io/service-account-token
data:
  token: $(base64 -w 0 /home/ubuntu/tools-belt/jenkins-agent-sa-token)
EOF

  # Apply Role
  cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: jenkins
  namespace: $namespace
  labels:
    app.kubernetes.io/name: 'jenkins'
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["create","delete","get","list","patch","update","watch"]
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create","delete","get","list","patch","update","watch"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get","list","watch"]
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get"]
EOF

  echo "Two files extracted:"
  echo "jenkins-agent-sa-token & eks-ca"

elif [ "$action" == "2" ]; then
  # Delete resources
  kubectl delete serviceaccount jenkins -n $namespace
  kubectl delete secret jenkins-secret -n $namespace
  kubectl delete role jenkins -n $namespace
fi

echo "Setup complete."
