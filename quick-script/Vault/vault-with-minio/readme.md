# Vault HA and MinIO KMS Integration Guide

This guide provides comprehensive instructions for setting up HashiCorp Vault in High Availability (HA) mode and integrating it with MinIO for KMS encryption capabilities in a Kubernetes environment.

## Prerequisites

- Kubernetes cluster
- Helm 3.x installed
- `kubectl` configured
- `jq` installed
- Storage class that supports ReadWriteOnce (RWO)

## Part 1: Vault HA Setup

### 1. Install Vault

First, add the HashiCorp Helm repository:
```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
```

Download and extract Vault Helm chart:
```bash
helm pull hashicorp/vault
tar -zxvf vault-*.tgz
```

Install Vault:
```bash
helm install vault vault/
```

### 2. Initialize and Unseal Vault

Initialize Vault and save keys:
```bash
# Initialize Vault and save keys
kubectl exec $VAULT_POD_NAME -- vault operator init \
  -key-shares=1 -key-threshold=1 -format=json > keys.json

# Extract keys
VAULT_UNSEAL_KEY=$(cat keys.json | jq -r ".unseal_keys_b64[]")
VAULT_ROOT_KEY=$(cat keys.json | jq -r ".root_token")

# Unseal Vault
kubectl exec $VAULT_POD_NAME -- vault operator unseal $VAULT_UNSEAL_KEY
```

### 3. Verify HA Setup

Check cluster health:
```bash
kubectl exec vault-0 -- vault operator raft list-peers
kubectl exec vault-0 -- vault status | grep HA
kubectl exec vault-0 -- vault operator raft autopilot state
```

## Part 2: Configure Vault for MinIO KMS

### 1. Configure KV Engine and Policies

Access Vault pod:
```bash
kubectl exec -it $VAULT_POD_NAME -- /bin/sh
export VAULT_TOKEN="$VAULT_ROOT_KEY"
```

Enable KV secrets engine:
```bash
vault secrets enable -version=1 kv
```

Create KES policy:
```bash
cat <<EOF > /vault/file/kes-policy.hcl
path "kv/*" {
  capabilities = ["create", "read", "delete", "update", "list"]
}
EOF

vault policy write kes-policy /vault/file/kes-policy.hcl
```

### 2. Configure AppRole Authentication

Enable and configure AppRole:
```bash
vault auth enable approle
vault write auth/approle/role/kes-server \
  token_num_uses=0 \
  secret_id_num_uses=0 \
  period=5m \
  policies=kes-policy

# Get credentials
ROLE_ID=$(vault read -format=json auth/approle/role/kes-server/role-id | jq -r '.data.role_id')
SECRET_ID=$(vault write -f -format=json auth/approle/role/kes-server/secret-id | jq -r '.data.secret_id')
```

## Part 3: MinIO Setup

### 1. Install MinIO Operator

```bash
helm repo add minio-operator https://operator.min.io
helm repo update
helm install minio-operator minio-operator/minio-operator
```

### 2. Deploy MinIO Tenant

Download and configure tenant:
```bash
helm pull minio-operator/tenant
tar -zxvf tenant-*.tgz
```

Edit `tenant/values.yaml` with your configuration:
```yaml
kes:
  replicas: 1
  configuration: |-
    address: :7373
    tls:
      key: /tmp/kes/server.key
      cert: /tmp/kes/server.crt
    admin:
      identity: ${MINIO_KES_IDENTITY}
    keystore:
      vault:
        endpoint: "http://vault.default.svc.cluster.local:8200"
        prefix: "my-minio"
        approle:
          id: "${ROLE_ID}"
          secret: "${SECRET_ID}"
          retry: 15s
```

Install MinIO tenant:
```bash
helm install minio-tenant tenant/
```

## Part 4: Testing Encryption

### 1. Configure MinIO Client

```bash
mc alias set myminio https://myminio-hl.default.svc.cluster.local:9000 \
  $MINIO_ACCESS_KEY $MINIO_SECRET_KEY
```

### 2. Test KMS Integration

Create and test encrypted bucket:
```bash
# Create KMS key
mc admin kms key create myminio test-encrypted-bucket-key

# Create encrypted bucket
mc mb myminio/testencryptedbucket
mc encrypt set sse-kms test-encrypted-key myminio/testencryptedbucket/

# Test encryption
echo "Hello" > test.txt
mc cp test.txt myminio/testencryptedbucket/
mc stat myminio/testencryptedbucket/test.txt

# Verify encryption status
mc admin kms key status myminio test-encrypted-bucket-key
```

## Troubleshooting

### Vault Issues
- Check Vault status: `kubectl exec vault-0 -- vault status`
- View Vault logs: `kubectl logs vault-0`
- Verify unsealing: `kubectl exec vault-0 -- vault operator unseal`

### MinIO Issues
- Check MinIO pods: `kubectl get pods -l app=minio`
- View KES logs: `kubectl logs -l app=kes`
- Verify KMS configuration: `mc admin kms key status`

## Security Considerations

1. Store unseal keys and root tokens securely
2. Rotate AppRole credentials regularly
3. Use TLS for all communications
4. Implement proper RBAC
5. Regular backup of Vault data

## Additional Resources

- [Vault Documentation](https://www.vaultproject.io/docs)
- [MinIO KMS Guide](https://min.io/docs/minio/linux/operations/server-side-encryption/configure-encryption-keys.html)
- [KES Documentation](https://github.com/minio/kes)
