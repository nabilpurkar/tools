# MinIO Integration with Azure Key Vault Guide

This guide walks you through setting up MinIO with Azure Key Vault for encryption key management. Written for beginners, it provides step-by-step instructions with detailed explanations.

## Prerequisites

- Azure Account with active subscription
- Kubernetes cluster running
- Helm 3.x installed
- `kubectl` configured
- `mc` (MinIO Client) installed

## Part 1: Azure Setup

### 1. Create Azure Key Vault

1. Go to [Azure Portal](https://portal.azure.com)
2. Navigate to "Create a resource"
3. Search for "Key Vault" and select it
4. Click "Create" and fill in:
   ```
   Subscription: Your subscription
   Resource Group: Create new (e.g., "minio-rg")
   Key vault name: Choose unique name (e.g., "minio-kv")
   Region: Your preferred region
   Pricing tier: Standard
   ```
5. On "Access Configuration" tab:
   - Select "Azure role-based access control (RBAC)"
6. Click "Review + Create" then "Create"

### 2. Create App Registration

1. Navigate to "Azure Active Directory" in Azure Portal
2. Go to "App registrations" → "New registration"
3. Configure:
   ```
   Name: minio-kes-app
   Supported account types: Accounts in this organizational directory only
   Redirect URI: Leave blank
   ```
4. Click "Register"
5. **Save these values** (you'll need them later):
   - Application (client) ID
   - Directory (tenant) ID

### 3. Create Client Secret

1. In your "minio-kes-app":
2. Go to "Certificates & secrets" → "Client secrets"
3. Click "New client secret"
   ```
   Description: MinIO KES Secret
   Expiry: 24 months (or as per your policy)
   ```
4. Click "Add"
5. **IMPORTANT**: Immediately copy and save the secret value
   - It will only be shown once
   - Store it securely

### 4. Set Up Permissions

In your Key Vault, go to "Access control (IAM)" and add these roles for your app:

```bash
Required Roles:
1. Key Vault Administrator
2. Key Vault Crypto Officer
3. Key Vault Crypto User
4. Key Vault Secrets Officer
5. Key Vault Certificate User
```

For each role:
1. Click "+ Add" → "Add role assignment"
2. Search for the role name
3. Select "User, group, or service principal"
4. Search for "minio-kes-app"
5. Select and assign

## Part 2: MinIO Setup

### 1. Install MinIO Operator

```bash
# Add MinIO operator repository
helm repo add minio-operator https://operator.min.io
helm repo update

# Install operator
helm install minio-operator minio-operator/minio-operator
```

### 2. Prepare Tenant Configuration

```bash
# Download tenant chart
helm pull minio-operator/tenant
tar -zxvf tenant-*.tgz
```

### 3. Configure Tenant

Create a `values.yaml` file:

```yaml
tenant:
  name: minio
  pools:
    - servers: 4
      volumesPerServer: 4
      size: 1Ti

kes:
  replicas: 2
  configuration: |-
    address: :7373
    admin:
      identity: ""
    tls:
      key: /tmp/kes/server.key
      cert: /tmp/kes/server.crt
    keystore:
      azure:
        keyvault:
          endpoint: "https://<your-kv-name>.vault.azure.net/"
          credentials:
            tenant_id: "<your-tenant-id>"
            client_id: "<your-client-id>"
            client_secret: "<your-client-secret>"
        key:
          name: "minio-key"
          version: ""
```

Replace the placeholders:
- `<your-kv-name>`: Your Azure Key Vault name
- `<your-tenant-id>`: Directory (tenant) ID from step 2
- `<your-client-id>`: Application (client) ID from step 2
- `<your-client-secret>`: Client secret from step 3

### 4. Deploy MinIO Tenant

```bash
# Install tenant
helm install minio-tenant tenant/ -f values.yaml

# Check deployment
kubectl get pods -l app=minio
```

### 5. Access MinIO Console

```bash
# Port forward the console service
kubectl port-forward svc/minio-tenant-console 9443:9443
```

Visit https://localhost:9443 in your browser.

## Part 3: Testing the Setup

### 1. Configure MinIO Client

```bash
# Set up MinIO client
mc alias set myminio https://minio-tenant-hl.default.svc.cluster.local:9000 \
  $MINIO_ACCESS_KEY $MINIO_SECRET_KEY

# Verify connection
mc alias ls myminio
```

### 2. Test Encryption

```bash
# Create encrypted bucket
mc mb myminio/encrypted-bucket

# Enable encryption
mc encrypt set sse-kms myminio/encrypted-bucket

# Test upload
echo "Hello" > test.txt
mc cp test.txt myminio/encrypted-bucket/

# Verify encryption
mc stat myminio/encrypted-bucket/test.txt
```

## Troubleshooting

### Common Issues

1. **Connection Issues**
   ```bash
   # Check pods
   kubectl get pods -l app=minio
   kubectl get pods -l app=kes

   # Check logs
   kubectl logs -l app=kes
   ```

2. **Azure Permissions**
   - Verify all 5 roles are assigned
   - Check Azure Portal → Key Vault → Access Control
   - Look for denied requests in Azure Activity Log

3. **KES Issues**
   ```bash
   # Check KES logs
   kubectl logs -l app=kes
   
   # Verify Azure connection
   kubectl exec -it kes-0 -- curl -v https://<your-kv-name>.vault.azure.net/
   ```

### Quick Fixes

1. **Pod not starting:**
   ```bash
   kubectl describe pod <pod-name>
   ```

2. **Authentication failures:**
   - Double-check tenant_id, client_id, and client_secret
   - Verify secret hasn't expired in Azure

3. **Network issues:**
   - Ensure Key Vault allows network access
   - Check if cluster can reach Azure

## Security Best Practices

1. **Credentials Management:**
   - Rotate client secret regularly
   - Use Kubernetes secrets for sensitive values
   - Enable audit logging

2. **Network Security:**
   - Configure network policies
   - Restrict Key Vault access
   - Enable TLS for all communications

3. **Monitoring:**
   - Set up alerts for failed operations
   - Monitor Key Vault access logs
   - Track secret expiration

## Additional Resources

- [Azure Key Vault Documentation](https://docs.microsoft.com/azure/key-vault)
- [MinIO Documentation](https://min.io/docs/minio/kubernetes/upstream/)
- [KES Documentation](https://github.com/minio/kes)

Need help? Review:
- Azure Key Vault logs
- KES pod logs
- MinIO operator logs
- Azure Activity Log for permission issues
