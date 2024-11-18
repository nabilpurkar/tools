# Complete Vault HA Installation and Testing Guide

This guide provides step-by-step instructions for installing, configuring, and testing HashiCorp Vault's High Availability (HA) setup in Kubernetes.

## Prerequisites
- Kubernetes cluster
- Helm 3.x installed
- `kubectl` configured
- `jq` installed
- Storage class that supports ReadWriteOnce (RWO)

## Installation Process

### 1. Add HashiCorp Helm Repository
```bash
# Add HashiCorp helm repo
helm repo add hashicorp https://helm.releases.hashicorp.com

# Update helm repos
helm repo update
```

### 2. Create Namespace (Optional)
```bash
kubectl create namespace vault
kubectl config set-context --current --namespace=vault
```

### 3. Install Vault using Helm
```bash
# Install Vault with HA configuration
helm install vault hashicorp/vault \
  --set server.ha.enabled=true \
  --set server.ha.replicas=3
  
# Wait for pods to be ready
kubectl wait --for=condition=Ready pod/vault-0
kubectl wait --for=condition=Ready pod/vault-1
kubectl wait --for=condition=Ready pod/vault-2

# Verify pods
kubectl get pods
```

### 4. Initialize and Unseal Vault

#### Option 1: Using Automated Script
```bash
# Clone the repository
git clone https://github.com/yourusername/vault-k8s-init.git
cd vault-k8s-init

# Make script executable
chmod +x scripts/vault-init-ha.sh

# Run script (with namespace if not using default)
./scripts/vault-init-ha.sh -n vault
```

#### Option 2: Manual Process
```bash
# Initialize Vault
kubectl exec -it vault-0 -- vault operator init > vault-keys.json

# Save keys securely
cp vault-keys.json keys/vault-keys.json
chmod 600 keys/vault-keys.json

# Unseal vault-0
kubectl exec -it vault-0 -- vault operator unseal # Enter key 1
kubectl exec -it vault-0 -- vault operator unseal # Enter key 2
kubectl exec -it vault-0 -- vault operator unseal # Enter key 3

# Join vault-1 to the cluster
kubectl exec -it vault-1 -- vault operator raft join http://vault-0.vault-internal:8200

# Unseal vault-1
kubectl exec -it vault-1 -- vault operator unseal # Enter key 1
kubectl exec -it vault-1 -- vault operator unseal # Enter key 2
kubectl exec -it vault-1 -- vault operator unseal # Enter key 3

# Join vault-2 to the cluster
kubectl exec -it vault-2 -- vault operator raft join http://vault-0.vault-internal:8200

# Unseal vault-2
kubectl exec -it vault-2 -- vault operator unseal # Enter key 1
kubectl exec -it vault-2 -- vault operator unseal # Enter key 2
kubectl exec -it vault-2 -- vault operator unseal # Enter key 3
```

## Initial Configuration

### 1. Login to Vault
```bash
# Get root token from vault-keys.json
ROOT_TOKEN=$(cat keys/vault-keys.json | jq -r '.root_token')

# Login
kubectl exec -it vault-0 -- vault login $ROOT_TOKEN
```

### 2. Enable KV Secrets Engine
```bash
# Enable KV version 2
kubectl exec -it vault-0 -- vault secrets enable -path=secret kv-v2
```

### 3. Create Test Secrets
```bash
# Create test secret
kubectl exec -it vault-0 -- vault kv put secret/test \
    username="testuser" \
    password="testpass"
```

## Verify Installation

### 1. Check Cluster Status
```bash
# Check raft peers
kubectl exec -it vault-0 -- vault operator raft list-peers

# Check vault status on all pods
for i in {0..2}; do
  echo "=== vault-$i status ==="
  kubectl exec -it vault-$i -- vault status
done
```

### 2. Verify Secret Access
```bash
# Read test secret
kubectl exec -it vault-0 -- vault kv get secret/test
```

### 3. Check HA Status
```bash
# Check leader status
for i in {0..2}; do
  echo "=== vault-$i leader status ==="
  kubectl exec -it vault-$i -- vault status | grep leader
done
```

## Basic HA Test

### 1. Test Leader Election
```bash
# Find current leader
kubectl exec -it vault-0 -- vault status | grep leader

# Delete leader pod
kubectl delete pod vault-0

# Watch new leader election
watch kubectl exec -it vault-1 -- vault status

# Unseal new pod after recreation
kubectl exec -it vault-0 -- vault operator unseal # Enter key 1
kubectl exec -it vault-0 -- vault operator unseal # Enter key 2
kubectl exec -it vault-0 -- vault operator unseal # Enter key 3
```

### 2. Verify Continuous Operation
```bash
# Login to a running pod
kubectl exec -it vault-1 -- vault login $ROOT_TOKEN

# Try accessing secrets
kubectl exec -it vault-1 -- vault kv get secret/test
```

## Backup Current Setup

### 1. Create Snapshot
```bash
# Create backup
kubectl exec -it vault-0 -- vault operator raft snapshot save /vault/data/backup.snap

# Copy to local machine
kubectl cp vault-0:/vault/data/backup.snap ./vault-backup.snap
```

## Important Notes
1. **Save Keys Securely**: 
   - Keep `vault-keys.json` in a secure location
   - Consider splitting unseal keys among trusted operators
   - Never store unseal keys in version control

2. **Regular Testing**:
   - Test backup restoration monthly
   - Verify HA failover quarterly
   - Document recovery time objectives (RTO)

3. **Monitoring**:
   - Set up alerts for seal status
   - Monitor raft peer status
   - Watch for failed unseal attempts

## Troubleshooting Common Issues

### Pod Won't Start
```bash
# Check pod events
kubectl describe pod vault-0

# Check logs
kubectl logs vault-0
```

### Unseal Issues
```bash
# Check seal status
kubectl exec -it vault-0 -- vault status

# Verify storage access
kubectl exec -it vault-0 -- ls -l /vault/data
```

### Raft Cluster Issues
```bash
# List peers
kubectl exec -it vault-0 -- vault operator raft list-peers

# Remove problematic peer
kubectl exec -it vault-0 -- vault operator raft remove-peer <node_id>
```

## Next Steps
1. Set up authentication methods
2. Configure audit logging
3. Implement backup automation
4. Set up monitoring and alerts
5. Document emergency procedures
6. Test failure scenarios (follow vault-ha-testing guide)

## References
- [Official Vault Documentation](https://www.vaultproject.io/docs)
- [Vault on Kubernetes Guide](https://www.vaultproject.io/docs/platform/k8s)
- [Vault HA Architecture](https://www.vaultproject.io/docs/internals/high-availability)

## Related Guides
- [Vault K8s Init](../vault-k8s-init/README.md) - Initialization scripts
- [Vault HA Testing](../vault-ha-testing/README.md) - Testing procedures

Would you like me to add any specific installation scenarios or expand any section further?
