# Vault Project Collection

A collection of HashiCorp Vault deployment patterns and integrations for Kubernetes, focusing on High Availability and MinIO KMS integration.

## Project Structure

```
vault/
├── minio-tenant-with-azure-kv/
│   └── readme.md            # Azure Key Vault integration guide
├── vault-ha-testing/
│   └── readme.md            # Vault HA testing procedures
├── vault-k8s-init/
│   ├── keys/               # Store for Vault keys (gitignored)
│   ├── scripts/
│   │   └── vault-init-ha.sh # Automated HA initialization
│   └── readme.md           # Init automation documentation
├── vault-with-minio/
│   └── readme.md           # Vault KMS integration guide
└── readme.md               # This file
```

## Projects Overview

1. **vault-ha-testing**: Test procedures and validation for Vault HA setup
2. **vault-k8s-init**: Automated initialization scripts for Vault HA
3. **vault-with-minio**: Integration guide for Vault as MinIO KMS
4. **minio-tenant-with-azure-kv**: Azure Key Vault integration for MinIO

## Getting Started

Choose the appropriate project based on your needs:
- For basic Vault HA setup: `vault-ha-testing`
- For automated initialization: `vault-k8s-init`
- For MinIO integration: `vault-with-minio`
- For Azure KV integration: `minio-tenant-with-azure-kv`
