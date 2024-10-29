#!/bin/bash

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    case $color in
        "red") echo -e "\033[31m${message}\033[0m" ;;
        "green") echo -e "\033[32m${message}\033[0m" ;;
        "yellow") echo -e "\033[33m${message}\033[0m" ;;
        "blue") echo -e "\033[34m${message}\033[0m" ;;
    esac
}

# Function to check if script is run as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_color "red" "This script must be run as root"
        exit 1
    fi
}

# Function to detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VERSION=$VERSION_ID
    else
        print_color "red" "Cannot detect OS"
        exit 1
    fi
}

# Function to validate Kubernetes version
validate_k8s_version() {
    local version=$1
    if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        print_color "red" "Invalid version format. Please use format: X.Y.Z (e.g., 1.28.0)"
        exit 1
    fi
}

# Function to set up prerequisites
setup_prerequisites() {
    print_color "green" "Setting up prerequisites..."
    
    # Disable swap
    swapoff -a
    sed -i '/swap/d' /etc/fstab
    
    # Load required kernel modules
    cat > /etc/modules-load.d/k8s.conf <<EOF
overlay
br_netfilter
EOF
    
    modprobe overlay
    modprobe br_netfilter
    
    # Set up required sysctl parameters
    cat > /etc/sysctl.d/k8s.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
    
    sysctl --system
}

# Function to install containerd
install_containerd() {
    print_color "green" "Installing containerd..."
    
    case $OS in
        "Ubuntu"|"Debian")
            apt-get update
            apt-get install -y containerd
            ;;
        "CentOS Linux"|"Red Hat Enterprise Linux")
            yum install -y yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y containerd.io
            ;;
    esac
    
    # Configure containerd
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    systemctl restart containerd
    systemctl enable containerd
}

# Function to install kubeadm, kubelet, and kubectl
install_kubernetes_packages() {
    local version=$1
    print_color "green" "Installing Kubernetes packages version $version..."
    
    case $OS in
        "Ubuntu"|"Debian")
            apt-get update
            apt-get install -y apt-transport-https ca-certificates curl gpg
            curl -fsSL https://pkgs.k8s.io/core:/stable:/v${version%.*}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
            echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${version%.*}/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
            apt-get update
            apt-get install -y kubelet=$version-* kubeadm=$version-* kubectl=$version-*
            apt-mark hold kubelet kubeadm kubectl
            ;;
            
        "CentOS Linux"|"Red Hat Enterprise Linux")
            cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v${version%.*}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v${version%.*}/rpm/repodata/repomd.xml.key
EOF
            yum install -y kubelet-$version kubeadm-$version kubectl-$version
            systemctl enable kubelet
            ;;
    esac
}

# Function to set up user permissions
setup_user_permissions() {
    local username=$1
    print_color "green" "Setting up Kubernetes access for user: $username"
    
    # Create .kube directory in user's home
    user_home=$(eval echo ~$username)
    mkdir -p $user_home/.kube
    cp -i /etc/kubernetes/admin.conf $user_home/.kube/config
    chown -R $username:$username $user_home/.kube
    
    # Add user to docker group if it exists
    if getent group docker >/dev/null; then
        usermod -aG docker $username
    fi
}

# Function to initialize master node
initialize_master() {
    local pod_network_cidr=$1
    print_color "green" "Initializing master node..."
    
    # Initialize with kubeadm
    kubeadm init --pod-network-cidr=$pod_network_cidr --upload-certs | tee /root/kubeadm-init.log
    
    # Wait for admin.conf to be created
    timeout=60
    while [ ! -f /etc/kubernetes/admin.conf ] && [ $timeout -gt 0 ]; do
        sleep 1
        ((timeout--))
    done
    
    if [ ! -f /etc/kubernetes/admin.conf ]; then
        print_color "red" "Error: admin.conf was not created. Please check the logs in /root/kubeadm-init.log"
        exit 1
    fi
    
    # Set up kubeconfig for root
    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config
    
    # Install Calico network plugin
    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml
    
    # Generate join command for worker nodes
    kubeadm token create --print-join-command > /root/worker-join.sh
    chmod +x /root/worker-join.sh
}

# Function to print cluster information
print_cluster_info() {
    local username=$1
    
    print_color "blue" "\n=== Kubernetes Cluster Setup Complete ==="
    echo "----------------------------------------------------------------"
    print_color "green" "Master Node Setup Completed Successfully!"
    echo "----------------------------------------------------------------"
    print_color "yellow" "Important Next Steps:"
    echo
    print_color "blue" "1. For the current non-root user ($username):"
    echo "   ✓ Kubernetes config has been set up automatically"
    echo "   ✓ Try running: kubectl get nodes"
    echo
    print_color "blue" "2. To add worker nodes to this cluster:"
    echo "   a) Copy the contents of /root/worker-join.sh to each worker node"
    echo "   b) On each worker node:"
    echo "      - Install prerequisites by running this script with '-w' flag"
    echo "      - Run the join command from worker-join.sh as root"
    echo
    print_color "blue" "3. Verify cluster status:"
    echo "   Run: kubectl get nodes"
    echo "   Wait for all nodes to show 'Ready' status"
    echo
    print_color "blue" "4. Worker node join command location:"
    echo "   The join command is saved in: /root/worker-join.sh"
    echo "   You can view it using: cat /root/worker-join.sh"
    echo
    print_color "yellow" "Note: It may take a few minutes for all nodes to become ready"
    echo "      and for the cluster to be fully operational."
    echo "----------------------------------------------------------------"
}

# Main script execution
main() {
    check_root
    detect_os
    
    # Check if this is a worker node installation
    if [[ "$1" == "-w" ]]; then
        print_color "green" "Setting up worker node prerequisites..."
        setup_prerequisites
        read -p "Enter Kubernetes version (e.g., 1.28.0): " K8S_VERSION
        validate_k8s_version $K8S_VERSION
        install_containerd
        install_kubernetes_packages $K8S_VERSION
        print_color "yellow" "Worker node preparation complete!"
        print_color "yellow" "Run the join command from the master node to complete setup"
        exit 0
    fi
    
    # Get Kubernetes version from user
    read -p "Enter Kubernetes version (e.g., 1.28.0): " K8S_VERSION
    validate_k8s_version $K8S_VERSION
    
    # Get node type from user
    read -p "Is this a master node? (y/n): " IS_MASTER
    
    # Get current non-root user
    SUDO_USER=${SUDO_USER:-$(whoami)}
    if [ "$SUDO_USER" = "root" ]; then
        read -p "Enter the name of the non-root user to configure: " SUDO_USER
    fi
    
    # Get pod network CIDR if master
    if [[ $IS_MASTER =~ ^[Yy]$ ]]; then
        read -p "Enter pod network CIDR (default: 192.168.0.0/16): " POD_NETWORK_CIDR
        POD_NETWORK_CIDR=${POD_NETWORK_CIDR:-"192.168.0.0/16"}
    fi
    
    setup_prerequisites
    install_containerd
    install_kubernetes_packages $K8S_VERSION
    
    if [[ $IS_MASTER =~ ^[Yy]$ ]]; then
        initialize_master $POD_NETWORK_CIDR
        setup_user_permissions $SUDO_USER
        print_cluster_info $SUDO_USER
    else
        print_color "yellow" "For worker nodes, run the join command from the master node"
    fi
}

# Execute main function with any passed arguments
main "$@"
