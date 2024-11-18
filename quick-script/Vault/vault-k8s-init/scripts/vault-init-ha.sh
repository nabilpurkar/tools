#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Create keys directory if it doesn't exist
KEYS_DIR="keys"
mkdir -p "$KEYS_DIR"

# File to store keys and token
KEYS_FILE="${KEYS_DIR}/vault-keys.json"

# Parse command line arguments
while getopts "n:r:" opt; do
  case $opt in
    n)
      NAMESPACE="$OPTARG"
      ;;
    r)
      RELEASE_NAME="$OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      echo "Usage: $0 [-n namespace] [-r release-name]" >&2
      exit 1
      ;;
  esac
done

# If namespace is not provided, use default
if [ -z "$NAMESPACE" ]; then
    NAMESPACE="default"
    echo -e "${BLUE}No namespace provided, using default namespace${NC}"
fi

# Try to detect Vault pods using different methods
echo -e "${BLUE}Detecting Vault pods in namespace ${NAMESPACE}...${NC}"

# Method 1: Try default label
VAULT_PODS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=vault -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

# Method 2: If no pods found and release name provided, try with release name
if [ -z "$VAULT_PODS" ] && [ ! -z "$RELEASE_NAME" ]; then
    echo -e "${BLUE}Trying to find pods with release name: $RELEASE_NAME${NC}"
    VAULT_PODS=$(kubectl get pods -n $NAMESPACE -l app.kubernetes.io/instance=$RELEASE_NAME -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
fi

# Method 3: Try to detect any pods running vault container
if [ -z "$VAULT_PODS" ]; then
    echo -e "${BLUE}Trying to detect any pods running Vault...${NC}"
    VAULT_PODS=$(kubectl get pods -n $NAMESPACE -o jsonpath='{.items[?(@.spec.containers[*].image=~".*vault.*")].metadata.name}' 2>/dev/null)
fi

# If still no pods found, list available pods for user to choose
if [ -z "$VAULT_PODS" ]; then
    echo -e "${BLUE}No Vault pods automatically detected. Available pods in namespace:${NC}"
    kubectl get pods -n $NAMESPACE -o wide
    echo -e "${RED}Please specify the release name using -r flag if Vault was installed with a different name${NC}"
    exit 1
fi

echo -e "${GREEN}Found Vault pods: $VAULT_PODS${NC}"

# Get the internal service name
if [ ! -z "$RELEASE_NAME" ]; then
    INTERNAL_SERVICE="${RELEASE_NAME}-vault-internal"
else
    INTERNAL_SERVICE="vault-internal"
fi

# Verify if the service exists
if ! kubectl get service -n $NAMESPACE $INTERNAL_SERVICE >/dev/null 2>&1; then
    echo -e "${BLUE}Detecting internal service name...${NC}"
    INTERNAL_SERVICE=$(kubectl get service -n $NAMESPACE -l app.kubernetes.io/name=vault-internal -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -z "$INTERNAL_SERVICE" ]; then
        echo -e "${RED}Could not detect internal service name. Please verify your Vault installation.${NC}"
        echo -e "${BLUE}Available services in namespace:${NC}"
        kubectl get services -n $NAMESPACE
        exit 1
    fi
fi

echo -e "${GREEN}Using internal service: $INTERNAL_SERVICE${NC}"

# Initialize Vault using the first pod
FIRST_POD=$(echo $VAULT_PODS | cut -d' ' -f1)
echo -e "${BLUE}Using pod $FIRST_POD for initialization${NC}"

# Check if Vault is already initialized
INIT_STATUS=$(kubectl exec -n $NAMESPACE $FIRST_POD -- vault status -format=json 2>/dev/null | jq -r '.initialized' || echo "false")

if [ "$INIT_STATUS" = "true" ]; then
    echo -e "${GREEN}Vault is already initialized${NC}"
    if [ ! -f "$KEYS_FILE" ]; then
        echo -e "${RED}Warning: Vault is initialized but no keys file found at $KEYS_FILE${NC}"
        exit 1
    fi
else
    echo -e "${BLUE}Initializing Vault...${NC}"
    kubectl exec -n $NAMESPACE $FIRST_POD -- vault operator init -format=json > $KEYS_FILE
    if [ $? -ne 0 ]; then
        echo -e "${RED}Failed to initialize Vault${NC}"
        exit 1
    fi
    echo -e "${GREEN}Vault initialized successfully${NC}"
fi

# Read unseal keys and root token
UNSEAL_KEYS=$(cat $KEYS_FILE | jq -r '.unseal_keys_b64[0:3][]')
ROOT_TOKEN=$(cat $KEYS_FILE | jq -r '.root_token')

# Function to unseal a pod
unseal_pod() {
    local pod=$1
    echo -e "${BLUE}Unsealing pod: $pod${NC}"
    
    # Check if pod is already unsealed
    SEAL_STATUS=$(kubectl exec -n $NAMESPACE $pod -- vault status -format=json 2>/dev/null | jq -r '.sealed' || echo "true")
    
    if [ "$SEAL_STATUS" = "false" ]; then
        echo -e "${GREEN}Pod $pod is already unsealed${NC}"
        return 0
    fi

    # Unseal using each key
    for key in $(echo "$UNSEAL_KEYS"); do
        echo -e "${BLUE}Applying unseal key to $pod...${NC}"
        kubectl exec -n $NAMESPACE $pod -- vault operator unseal "$key"
        if [ $? -ne 0 ]; then
            echo -e "${RED}Failed to apply key to pod $pod${NC}"
            continue
        fi
    done
}

# First unseal the primary pod
echo -e "${BLUE}Unsealing primary pod first...${NC}"
unseal_pod $FIRST_POD

# Login to Vault with root token on primary pod
echo -e "${BLUE}Logging into Vault on primary pod...${NC}"
kubectl exec -n $NAMESPACE $FIRST_POD -- sh -c "VAULT_TOKEN='$ROOT_TOKEN' vault login $ROOT_TOKEN" >/dev/null

# Wait for leader to be ready
echo -e "${BLUE}Waiting for leader to be ready...${NC}"
sleep 10

# Join other pods to the Raft cluster
for pod in $VAULT_PODS; do
    if [ "$pod" != "$FIRST_POD" ]; then
        echo -e "${BLUE}Joining $pod to Raft cluster...${NC}"
        
        # Construct the join address using the internal service DNS
        JOIN_ADDR="http://${FIRST_POD}.${INTERNAL_SERVICE}.${NAMESPACE}.svc:8200"
        
        echo -e "${BLUE}Using join address: $JOIN_ADDR${NC}"
        
        # Join the raft cluster with retry mechanism
        RETRY_COUNT=0
        MAX_RETRIES=3
        
        while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
            kubectl exec -n $NAMESPACE $pod -- sh -c "VAULT_ADDR='http://localhost:8200' vault operator raft join '$JOIN_ADDR'"
            if [ $? -eq 0 ]; then
                break
            fi
            RETRY_COUNT=$((RETRY_COUNT + 1))
            echo -e "${BLUE}Retry $RETRY_COUNT of $MAX_RETRIES...${NC}"
            sleep 5
        done
        
        # Now unseal the pod
        unseal_pod $pod
    fi
done

# Verify status of all pods
echo -e "${BLUE}Verifying status of all pods...${NC}"
for pod in $VAULT_PODS; do
    echo -e "${BLUE}Status for pod: $pod${NC}"
    kubectl exec -n $NAMESPACE $pod -- vault status || true
done

# Print root token
echo -e "${GREEN}Vault initialization and unsealing completed!${NC}"
echo -e "${BLUE}Root Token: ${GREEN}$ROOT_TOKEN${NC}"
echo -e "${RED}IMPORTANT: Keep the $KEYS_FILE file secure. You will need these keys to unseal the vault after a restart.${NC}"

# Verify HA status using root token
echo -e "${BLUE}Checking HA status...${NC}"
kubectl exec -n $NAMESPACE $FIRST_POD -- sh -c "VAULT_TOKEN='$ROOT_TOKEN' vault operator raft list-peers"

# Print final cluster status
echo -e "${BLUE}Final Cluster Status:${NC}"
for pod in $VAULT_PODS; do
    echo -e "${BLUE}Pod $pod status:${NC}"
    kubectl exec -n $NAMESPACE $pod -- sh -c "VAULT_TOKEN='$ROOT_TOKEN' vault status" || true
done

echo -e "${GREEN}Script completed successfully!${NC}"
