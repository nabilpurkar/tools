# Vault HA and MinIO KMS Integration Guide

This guide provides comprehensive instructions for setting up HashiCorp Vault in High Availability (HA) mode and integrating it with MinIO for KMS encryption capabilities in a Kubernetes environment.

## Prerequisites

- Kubernetes cluster
- Helm 3.x installed
- `kubectl` configured
- `jq` installed
- Storage class that supports ReadWriteOnce (RWO)
- `mc` (MinIO Client) installed

## Part 1: Vault HA Setup

### 1. Install Vault

Add the HashiCorp Helm repository:
```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
```

Download and prepare Vault chart:
```bash
helm pull hashicorp/vault
tar -zxvf vault-*.tgz
```

Install Vault in HA mode:
```bash
helm install vault hashicorp/vault \
  --set server.ha.enabled=true \
  --set server.ha.replicas=3 \
  --set 'server.ha.raft.enabled=true' \
  --set 'server.ha.raft.setNodeId=true'
```

Wait for pods to be ready:
```bash
kubectl wait --for=condition=Ready pod/vault-0
kubectl wait --for=condition=Ready pod/vault-1
kubectl wait --for=condition=Ready pod/vault-2
```

### 2. Initialize and Unseal Vault Cluster

Initialize only the first Vault pod (vault-0):
```bash
# Initialize Vault and save keys
kubectl exec vault-0 -- vault operator init \
  -key-shares=1 -key-threshold=1 -format=json > keys.json

# Extract and save keys securely
VAULT_UNSEAL_KEY=$(cat keys.json | jq -r ".unseal_keys_b64[]")
VAULT_ROOT_KEY=$(cat keys.json | jq -r ".root_token")

# Save keys to environment (temporary)
echo "export VAULT_UNSEAL_KEY=$VAULT_UNSEAL_KEY" >> ~/.bashrc
echo "export VAULT_ROOT_KEY=$VAULT_ROOT_KEY" >> ~/.bashrc
source ~/.bashrc
```

Unseal all Vault pods and establish the Raft cluster:
```bash
# Unseal vault-0 (will become leader)
kubectl exec vault-0 -- vault operator unseal $VAULT_UNSEAL_KEY

# Join vault-1 to the cluster and unseal
kubectl exec vault-1 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec vault-1 -- vault operator unseal $VAULT_UNSEAL_KEY

# Join vault-2 to the cluster and unseal
kubectl exec vault-2 -- vault operator raft join http://vault-0.vault-internal:8200
kubectl exec vault-2 -- vault operator unseal $VAULT_UNSEAL_KEY
```

### 3. Verify HA Setup

Check cluster health and leadership:
```bash
# List all Raft peers
kubectl exec vault-0 -- vault operator raft list-peers

# Check leader status
kubectl exec vault-0 -- vault status | grep HA

# Verify Raft cluster state
kubectl exec vault-0 -- vault operator raft autopilot state
```

Expected output for a healthy cluster:
```
# Raft peers list should show all nodes
Node                                    Address                        State       Voter
----                                    -------                        -----       -----
vault-0                                vault-0.vault-internal:8201     leader      true
vault-1                                vault-1.vault-internal:8201     follower    true
vault-2                                vault-2.vault-internal:8201     follower    true
```

## Part 2: Configure Vault for MinIO KMS

### 1. Configure KV Engine and Policies

Access Vault pod and set token:
```bash
kubectl exec -it vault-0 -- /bin/sh
export VAULT_TOKEN="$VAULT_ROOT_KEY"
```

Enable KV secrets engine and create policy:
```bash
# Enable KV engine
vault secrets enable -version=1 kv

# Create KES policy
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
# Enable AppRole auth
vault auth enable approle

# Configure KES role
vault write auth/approle/role/kes-server \
  token_num_uses=0 \
  secret_id_num_uses=0 \
  period=5m \
  policies=kes-policy

# Get and save credentials
ROLE_ID=$(vault read -field=role_id auth/approle/role/kes-server/role-id)
SECRET_ID=$(vault write -f -field=secret_id auth/approle/role/kes-server/secret-id)

echo "Role ID: $ROLE_ID"
echo "Secret ID: $SECRET_ID"
```

## Part 3: MinIO Setup

### 1. Install MinIO Operator

```bash
helm repo add minio-operator https://operator.min.io
helm repo update
helm install minio-operator minio-operator/minio-operator
```

### 2. Deploy MinIO Tenant

Download and prepare tenant configuration:
```bash
helm pull minio-operator/tenant
tar -zxvf tenant-*.tgz
```

Edit `tenant/values.yaml` with KES configuration:
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
        status:
          ping: 10s
```

Install MinIO tenant:
```bash
helm install minio-tenant tenant/
```

### 3. Access MinIO Console

```bash
kubectl port-forward svc/myminio-console 9443:9443
```

Visit https://localhost:9443 in your browser.

## Part 4: Testing Encryption

### 1. Configure MinIO Client

```bash
# Configure MinIO client
mc alias set myminio https://myminio-hl.default.svc.cluster.local:9000 \
  $MINIO_ACCESS_KEY $MINIO_SECRET_KEY

# Verify connection
mc alias ls myminio
```

### 2. Test KMS Integration

Create and test encrypted bucket:
```bash
# Create KMS key
mc admin kms key create myminio test-encrypted-bucket-key

# Create and configure encrypted bucket
mc mb myminio/testencryptedbucket
mc encrypt set sse-kms test-encrypted-key myminio/testencryptedbucket/

# Test encryption
echo "Hello" > test.txt
mc cp test.txt myminio/testencryptedbucket/

# Verify encryption
mc stat myminio/testencryptedbucket/test.txt
mc admin kms key status myminio test-encrypted-bucket-key
```

Expected encryption status output:
```
Key: test-encrypted-bucket-key
  - Encryption ✔
  - Decryption ✔
```

## Troubleshooting

### Vault HA Issues

Check pod status:
```bash
kubectl get pods -l app.kubernetes.io/name=vault
```

If a pod becomes sealed:
```bash
# Check seal status
kubectl exec vault-N -- vault status | grep Sealed

# Unseal if needed
kubectl exec vault-N -- vault operator unseal $VAULT_UNSEAL_KEY
```

If a pod loses Raft membership:
```bash
# Rejoin the Raft cluster
kubectl exec vault-N -- vault operator raft join http://vault-0.vault-internal:8200
```

### MinIO/KES Issues

Check KES logs:
```bash
kubectl logs -l app=kes
```

Verify Vault connectivity:
```bash
kubectl exec -it kes-0 -- curl -v http://vault.default.svc.cluster.local:8200/v1/sys/health
```

## Security Considerations

1. **Key Management:**
   - Store unseal keys and root tokens securely in a production vault
   - Use multiple key shares in production
   - Regularly rotate AppRole credentials

2. **Network Security:**
   - Enable TLS for all communications
   - Configure proper network policies
   - Use internal service names for communication

3. **Access Control:**
   - Implement proper RBAC
   - Use minimum required policies
   - Regularly audit access logs

4. **Backup and Recovery:**
   - Regular backup of Vault data
   - Document and test recovery procedures
   - Maintain backup of encryption keys

## Additional Resources

- [Vault Documentation](https://www.vaultproject.io/docs)
- [Vault HA Guide](https://www.vaultproject.io/docs/concepts/ha)
- [MinIO KMS Guide](https://min.io/docs/minio/linux/operations/server-side-encryption/configure-encryption-keys.html)
- [KES Documentation](https://github.com/minio/kes)

## Maintenance Tasks

### Regular Maintenance

1. Check Vault cluster health:
```bash
kubectl exec vault-0 -- vault operator raft list-peers
```

2. Verify KMS key status:
```bash
mc admin kms key status myminio test-encrypted-bucket-key
```

3. Update certificates before expiry:
```bash
# Check certificate expiry
kubectl exec vault-0 -- vault operator raft list-peers -format=json | jq -r '.data.configs."vault-0".TLS_info.cert_expiry'
```

### Backing Up Vault

```bash
# Snapshot Vault data
kubectl exec vault-0 -- vault operator raft snapshot save /tmp/raft-backup.snap
kubectl cp vault-0:/tmp/raft-backup.snap ./raft-backup.snap
```

Remember to regularly test your backups and maintain documentation of all custom configurations and procedures.
