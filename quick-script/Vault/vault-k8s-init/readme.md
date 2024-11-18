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
The script can be run with or without specifying a namespace:

### With specific namespace:
```bash
./scripts/vault-init-ha.sh -n my-namespace
```

### Using default namespace:
```bash
./scripts/vault-init-ha.sh
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

## 🤝 Contributing
Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## 📄 License
This project is licensed under the MIT License - see the LICENSE file for details

## 📧 Contact
For support or questions, please open an issue in the GitHub repository.
