# Vault HA Cluster Initialization Script
This repository contains a script to automate the initialization and unsealing of HashiCorp Vault in a Kubernetes High Availability (HA) configuration using Raft storage backend.

## 📁 Folder Structure
```
vault-k8s-init/
├── README.md
├── scripts/
│   └── vault-init-ha.sh
└── keys/
    └── .gitignore    # To ensure no keys are accidentally committed
```

## 🚀 Features
- Automatic Vault initialization in Kubernetes
- Support for multi-pod HA setup with Raft storage
- Automatic unsealing of all Vault pods
- Raft cluster configuration
- Namespace support for multi-tenant clusters
- Colored output for better readability
- Secure key storage
- Retry mechanism for cluster join operations

## 📋 Prerequisites
- Kubernetes cluster with Vault pods deployed
- `kubectl` configured with appropriate cluster access
- `jq` installed on the system running the script
- Vault pods labeled with `app.kubernetes.io/name=vault`

## 🔧 Installation
1. Clone this repository:
```bash
git clone https://github.com/yourusername/vault-k8s-init.git
cd vault-k8s-init
```

2. Make the script executable:
```bash
chmod +x scripts/vault-init-ha.sh
```

## 📝 Usage

### Automated Method
The script can be run with or without specifying a namespace:

#### With specific namespace:
```bash
./scripts/vault-init-ha.sh -n my-namespace
```

#### Using default namespace:
```bash
./scripts/vault-init-ha.sh
```

### Manual Steps
If you prefer to initialize and unseal Vault manually, follow these steps:

1. **Get the list of Vault pods**
```bash
# Replace 'your-namespace' with your namespace
kubectl get pods -n your-namespace -l app.kubernetes.io/name=vault
```

2. **Initialize Vault** (only on one pod)
```bash
# Initialize and save the output
kubectl exec -n your-namespace vault-0 -- vault operator init
```
Save the output safely - it contains unseal keys and root token.

3. **Unseal the first pod**
```bash
# Run this command 3 times with different unseal keys
kubectl exec -n your-namespace vault-0 -- vault operator unseal
# Enter unseal key when prompted
```

4. **Login to Vault**
```bash
# Use the root token from initialization
kubectl exec -n your-namespace vault-0 -- vault login
# Enter root token when prompted
```

5. **Join other pods to Raft cluster** (for each additional pod)
```bash
# Get the join address
JOIN_ADDR="http://vault-0.vault-internal.your-namespace.svc:8200"

# Join the cluster
kubectl exec -n your-namespace vault-1 -- sh -c \
  "VAULT_ADDR='http://localhost:8200' vault operator raft join '$JOIN_ADDR'"
```

6. **Unseal additional pods**
```bash
# For each additional pod (e.g., vault-1, vault-2)
# Run this command 3 times with different unseal keys
kubectl exec -n your-namespace vault-1 -- vault operator unseal
# Enter unseal key when prompted
```

7. **Verify cluster status**
```bash
# Check raft peers
kubectl exec -n your-namespace vault-0 -- vault operator raft list-peers

# Check vault status
kubectl exec -n your-namespace vault-0 -- vault status
```

8. **Optional: Store keys securely**
```bash
# Create keys directory
mkdir -p keys

# Store keys (replace with your actual keys)
cat > keys/vault-keys.json << EOF
{
  "unseal_keys_b64": [
    "key1",
    "key2",
    "key3",
    "key4",
    "key5"
  ],
  "root_token": "your-root-token"
}
EOF

# Secure the file
chmod 600 keys/vault-keys.json
```

## 🔑 Key Storage
- The script generates a `vault-keys.json` file in the `keys/` directory
- This file contains sensitive information including:
  - Unseal keys (encoded in base64)
  - Root token
- ⚠️ IMPORTANT: Keep this file secure and backed up safely

## 📊 Output
The script provides detailed output including:
- Initialization status
- Unsealing progress
- Raft cluster join status
- Final cluster status
- Root token (for initial setup)

## ⚠️ Security Considerations
1. Store the generated `vault-keys.json` securely
2. Rotate the root token after initial setup
3. Consider implementing proper key sharing mechanisms for production
4. Do not commit the keys directory to version control
5. When performing manual steps, secure the unseal keys and root token immediately
6. Consider using Vault's auto-unseal feature for production environments

## 🔄 What the Script Does
1. Checks if Vault is initialized
2. Initializes Vault if needed
3. Stores initialization keys and token
4. Unseals the primary pod
5. Joins secondary pods to the Raft cluster
6. Unseals secondary pods
7. Verifies the cluster status

## 🐛 Troubleshooting
- If pods fail to join the cluster:
  - Check network connectivity between pods
  - Verify service DNS resolution
  - Check the logs using `kubectl logs -n <namespace> <pod-name>`
- If unsealing fails:
  - Verify the keys in `vault-keys.json`
  - Check pod status and logs
  - Ensure proper permissions for the service account
- Manual debugging:
  - Use `kubectl exec -it <pod-name> -- sh` to get shell access
  - Check Vault logs: `kubectl logs <pod-name>`
  - Verify network connectivity between pods

## 🤝 Contributing
Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## 📄 License
This project is licensed under the MIT License - see the LICENSE file for details

## 📧 Contact
For support or questions, please open an issue in the GitHub repository.
