# Kubernetes Offline Upgrade Script

A bash script for performing offline upgrades of Kubernetes clusters. This script helps automate the process of downloading packages, saving container images, transferring files, and performing upgrades on both master and worker nodes.

## Features

- Download required upgrade packages
- Save container images for offline use
- Transfer files to worker nodes
- Load container images on offline nodes
- Upgrade master nodes
- Upgrade worker nodes

## Prerequisites

- A working Kubernetes cluster
- Root/sudo access on nodes
- SSH access to worker nodes
- Internet access on the download node (for initial package/image download)

## Current Version Support

The script currently supports upgrading to:
- Kubernetes: 1.29.2
- Calico: v3.27.2
- Containerd: 1.7.14
- etcd: 3.5.10-0
- CoreDNS: v1.11.1

## Usage

1. Clone the repository and make the script executable:
```bash
chmod +x k8s_upgrade.sh
```

2. Run the script:
```bash
./k8s_upgrade.sh
```

## Workflow

### 1. Download Packages (Internet Required)
- Downloads all necessary RPM packages
- Creates proper directory structure
- Saves packages for offline installation

### 2. Save Images (Internet Required)
- Pulls required container images
- Saves images as tar files
- Creates manifest of saved images

### 3. Transfer Files
- Transfers packages and images to target nodes
- Supports both password and SSH key authentication
- Verifies transfer completion

### 4. Load Images (Offline)
- Loads saved container images on target nodes
- Verifies image loading
- Shows detailed progress

### 5. Upgrade Master Node
- Upgrades control plane components
- Handles both single and multi-master setups
- Performs rolling upgrades

### 6. Upgrade Worker Node
- Upgrades worker node components
- Maintains cluster functionality
- Handles dependencies

## Manual Commands for Version Check

After adding the Kubernetes repository, you can check available versions using these commands:

```bash
# Add the Kubernetes repository
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
EOF

# Clean and update repos
sudo yum clean all
sudo yum makecache

# Check available versions
sudo yum list --showduplicates kubeadm --disableexcludes=kubernetes
sudo yum list --showduplicates kubelet --disableexcludes=kubernetes
sudo yum list --showduplicates kubectl --disableexcludes=kubernetes
```

## Directory Structure

```
~/k8s_upgrade/
├── packages/
│   ├── kubeadm/       # RPM packages
│   └── images/        # Container image tars
```

## Important Notes

1. **Backup Before Upgrade**
   - Always backup your cluster configuration
   - Take etcd snapshots if possible
   - Document current settings

2. **Verification Steps**
   - Check node status after each step
   - Verify pod functionality
   - Test cluster operations

3. **Recovery**
   - Keep old package versions
   - Document rollback procedures
   - Maintain backup configurations

## Troubleshooting

1. **Image Pull Issues**
   ```bash
   # Check available images
   sudo crictl images
   
   # Verify image presence
   sudo crictl inspecti [image_name]
   ```

2. **Package Installation Issues**
   ```bash
   # Check package status
   rpm -qa | grep -E "kube|cri"
   
   # Verify dependencies
   rpm -qpR [package_name].rpm
   ```

3. **Node Status Issues**
   ```bash
   # Check node status
   kubectl get nodes
   
   # Check component status
   kubectl get pods -n kube-system
   ```

## Contributing

Feel free to submit issues, fork the repository, and create pull requests for any improvements.

## License

This script is provided "as is" without warranty of any kind, either expressed or implied.
