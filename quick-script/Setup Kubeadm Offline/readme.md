# Kubernetes Offline Installation Tool

This tool facilitates the offline installation of Kubernetes clusters on CentOS/RHEL systems. It automates the process of downloading required packages, saving container images, and setting up both master and worker nodes in an offline environment.

## Version Information

Current configured versions:
- Kubernetes: 1.28.15
- Containerd: 1.7.14
- CNI Plugins: v1.3.0
- Calico: v3.26.1
- Pause: 3.9
- ETCD: 3.5.15-0
- CoreDNS: v1.10.1

## Prerequisites

- CentOS 7/8 or RHEL 7/8
- Minimum 2 CPU cores
- Minimum 2GB RAM
- Internet connection (only for the download phase)
- Root or sudo access
- SSH access between nodes (for file transfer)

## Installation Steps

### 1. Prepare an Online Machine

This machine will be used to download all necessary packages and images.

```bash
# Clone the repository
git clone <repository-url>
cd kubernetes-offline-installer

# Make the script executable
chmod +x install.sh

# Run the script
./install.sh
```

### 2. Download Required Components (Option 1)

On the online machine:
1. Select option 1 from the menu to download packages
2. Choose 'master' or 'worker' based on your needs
3. Select option 2 to save container images
4. Wait for the downloads to complete

### 3. Transfer Files (Option 3)

Transfer the downloaded packages to offline machines using either:
- SSH key authentication
- Password authentication

### 4. Install Components (Option 4)

On each offline machine:
1. Select option 4 to install packages
2. Choose 'master' or 'worker' based on the node type
3. Wait for installation to complete

### 5. Load Images (Option 5)

Load the container images on each node:
1. Select option 5 from the menu
2. Specify the node type
3. Provide the path to the installation packages

### 6. Setup Nodes

For Master Node:
1. Select option 6
2. Choose initialization method (offline/online)
3. Follow the prompts

For Worker Nodes:
1. Select option 7
2. Enter the join command from master node

## Customizing Versions

To use different versions of components, modify the following variables at the beginning of the script:

```bash
# Kubernetes versions
K8S_VERSION="1.28.15"               # Main Kubernetes version
KUBERNETES_REPO_VERSION="v1.28"     # Repository version
KUBELET_VERSION="1.28.15-150500.1.1"
KUBEADM_VERSION="1.28.15-150500.1.1"
KUBECTL_VERSION="1.28.15-150500.1.1"

# Component versions
CONTAINERD_VERSION="1.7.14"
CNI_VERSION="v1.3.0"
CALICO_VERSION="v3.26.1"
PAUSE_REGISTRY_VERSION=3.9
ETCD_IMAGE_VERSION=3.5.15-0
CORE_DNS_IMAGE_VERSION=v1.10.1
```

### Version Compatibility Matrix

When changing versions, ensure compatibility between components:

| Kubernetes Version | Compatible Containerd | Compatible CNI | Compatible Calico |
|-------------------|----------------------|----------------|-------------------|
| 1.28.x           | 1.7.x               | 1.3.x         | 3.26.x           |
| 1.27.x           | 1.6.x               | 1.2.x         | 3.25.x           |
| 1.26.x           | 1.6.x               | 1.2.x         | 3.24.x           |

## Network Configuration

Default network configurations:
- Pod Network CIDR: 10.244.0.0/16
- CNI: Calico
- Network Plugin: containerd

To modify network settings, update:
```bash
POD_NETWORK_CIDR="10.244.0.0/16"
```

## Troubleshooting

### Common Issues

1. **Container runtime not running:**
   ```bash
   sudo systemctl status containerd
   sudo journalctl -u containerd
   ```

2. **Images not loading:**
   ```bash
   sudo crictl images
   sudo crictl pull <image-name>
   ```

3. **Join command issues:**
   - Generate new join command using option 8
   - Verify network connectivity between nodes

### Logs Location

- Containerd: `/var/log/containerd`
- Kubelet: `/var/log/messages` or `journalctl -u kubelet`
- Kubernetes: `/var/log/kubernetes`

## Security Considerations

1. Always change default configurations in production:
   - Update network policies
   - Configure RBAC properly
   - Secure etcd communication

2. Protect sensitive files:
   - `/etc/kubernetes/admin.conf`
   - Join command tokens
   - Certificate keys

## Support

For issues and feature requests:
1. Check the troubleshooting section
2. Review logs in `/var/log/`
3. Create an issue in the repository

## License

[Specify your license here]

## Contributing

1. Fork the repository
2. Create a feature branch
3. Submit a pull request

## Acknowledgments

- Kubernetes community
- Calico project
- Containerd project
