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
- Automatic detection of Vault pods with multiple methods
- Support for custom release names
- Automatic internal service detection
- Raft cluster configuration
- Namespace support for multi-tenant clusters
- Colored output for better readability
- Secure key storage
- Retry mechanism for cluster join operations

## 📋 Prerequisites
- Kubernetes cluster with Vault pods deployed
- `kubectl` configured with appropriate cluster access
- `jq` installed on the system running the script
- Vault pods deployed (supports various labeling schemes)

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
The script can be run with different options:

#### Basic Usage (default namespace):
```bash
./scripts/vault-init-ha.sh
```

#### With specific namespace:
```bash
./scripts/vault-init-ha.sh -n my-namespace
```

#### With custom Vault release name:
```bash
./scripts/vault-init-ha.sh -r my-vault
```

#### With both namespace and release name:
```bash
./scripts/vault-init-ha.sh -n my-namespace -r my-vault
```

The script will automatically:
1. Detect Vault pods using multiple methods:
   - Standard Vault labels
   - Release name labels
   - Container image detection
2. Find the correct internal service name
3. Initialize and unseal the cluster

### Manual Steps
If you prefer to initialize and unseal Vault manually, follow these steps:

1. **Get the list of Vault pods**
```bash
# Method 1: Using standard labels
kubectl get pods -n your-namespace -l app.kubernetes.io/name=vault

# Method 2: Using release name
kubectl get pods -n your-namespace -l app.kubernetes.io/instance=your-release-name

# Method 3: List all pods to find Vault pods
kubectl get pods -n your-namespace
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

5. **Find the internal service name**
```bash
# List services to find the internal service
kubectl get services -n your-namespace

# The service name might be:
# - vault-internal (default)
# - your-release-name-internal (custom release)
```

6. **Join other pods to Raft cluster** (for each additional pod)
```bash
# Get the join address (replace service-name with your internal service)
JOIN_ADDR="http://vault-0.service-name.your-namespace.svc:8200"

# Join the cluster
kubectl exec -n your-namespace vault-1 -- sh -c \
  "VAULT_ADDR='http://localhost:8200' vault operator raft join '$JOIN_ADDR'"
```

[Rest of the manual steps remain the same...]

## 🔑 Key Storage
[Section remains the same...]

## 📊 Output
The script provides detailed output including:
- Pod detection results
- Service detection results
- Initialization status
- Unsealing progress
- Raft cluster join status
- Final cluster status
- Root token (for initial setup)

## ⚠️ Security Considerations
[Previous considerations remain, plus:]
7. Review detected pods before proceeding with initialization
8. Verify the internal service name is correct
9. Consider using explicit release names in production environments

## 🔄 What the Script Does
1. Detects Vault pods using multiple methods
2. Identifies the correct internal service name
3. Checks if Vault is initialized
4. Initializes Vault if needed
5. Stores initialization keys and token
6. Unseals the primary pod
7. Joins secondary pods to the Raft cluster
8. Unseals secondary pods
9. Verifies the cluster status

## 🐛 Troubleshooting
[Previous troubleshooting points remain, plus:]
- If pod detection fails:
  - Check if pods are properly labeled
  - Specify release name using -r flag
  - Verify pod names and running status
- If service detection fails:
  - Check if services are properly created
  - Verify service labels and names
  - Check namespace permissions

## 🤝 Contributing
Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## 📄 License
This project is licensed under the MIT License - see the LICENSE file for details

## 📧 Contact
For support or questions, please open an issue in the GitHub repository.
