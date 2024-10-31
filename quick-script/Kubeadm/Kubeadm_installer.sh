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

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ ! $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        print_color "red" "Invalid IP address format"
        return 1
    fi
    return 0
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

# Function to initialize first master node
initialize_first_master() {
    local pod_network_cidr=$1
    local api_server_ip=$2
    print_color "green" "Initializing first master node..."
    
    # Initialize with kubeadm
    kubeadm init \
        --control-plane-endpoint "${api_server_ip}:6443" \
        --pod-network-cidr=$pod_network_cidr \
        --upload-certs \
        | tee /root/kubeadm-init.log
    
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
    
    # Generate join commands
    print_color "green" "Generating join commands..."
    
    # Generate control plane join command
    kubeadm init phase upload-certs --upload-certs | grep -v "upload-certs" > /root/certificate-key.txt
    CERT_KEY=$(tail -1 /root/certificate-key.txt)
    
    kubeadm token create --print-join-command > /root/worker-join.txt
    JOIN_COMMAND=$(cat /root/worker-join.txt)
    
    # Create control-plane join command
    echo "$JOIN_COMMAND --control-plane --certificate-key $CERT_KEY" > /root/control-plane-join.txt
    
    # Secure the files
    chmod 600 /root/certificate-key.txt /root/worker-join.txt /root/control-plane-join.txt
}

# Function to join additional master node
join_control_plane() {
    local join_command=$1
    print_color "green" "Joining additional control plane node..."
    
    # Execute the join command
    $join_command
    
    # Set up kubeconfig
    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config
}

# Function to join worker node
join_worker() {
    local join_command=$1
    print_color "green" "Joining worker node..."
    
    # Execute the join command
    $join_command
}

# Function to set up user permissions
setup_user_permissions() {
    local username=$1
    print_color "green" "Setting up Kubernetes access for user: $username"
    
    user_home=$(eval echo ~$username)
    mkdir -p $user_home/.kube
    cp -i /etc/kubernetes/admin.conf $user_home/.kube/config
    chown -R $username:$username $user_home/.kube
    
    if getent group docker >/dev/null; then
        usermod -aG docker $username
    fi
}

# Function to print cluster information
print_cluster_info() {
    local username=$1
    local node_type=$2
    
    print_color "blue" "\n=== Kubernetes Cluster Setup Complete ==="
    echo "----------------------------------------------------------------"
    print_color "green" "$node_type Setup Completed Successfully!"
    echo "----------------------------------------------------------------"
    
    case $node_type in
        "First Master Node")
            print_color "yellow" "Important Information:"
            echo
            print_color "blue" "1. Join commands have been generated:"
            echo "   - For additional control plane nodes: /root/control-plane-join.txt"
            echo "   - For worker nodes: /root/worker-join.txt"
            echo "   - Certificate key (needed for control plane joins): /root/certificate-key.txt"
            echo
            print_color "yellow" "SECURITY NOTE: These files contain sensitive information!"
            echo "Transfer them securely to other nodes and delete when done."
            ;;
            
        "Additional Master Node")
            print_color "blue" "1. This node has joined the cluster as an additional control plane node"
            echo "   Verify by running: kubectl get nodes"
            ;;
            
        "Worker Node")
            print_color "blue" "1. This node has joined the cluster as a worker node"
            echo "   On the master node, verify by running: kubectl get nodes"
            ;;
    esac
    
    echo
    print_color "yellow" "Note: It may take a few minutes for all nodes to become ready"
    echo "      and for the cluster to be fully operational."
    echo "----------------------------------------------------------------"
}

# Function to show menu
show_menu() {
    print_color "blue" "\nKubernetes Cluster Setup Menu"
    echo "1. Install First Master Node"
    echo "2. Install Additional Master Node"
    echo "3. Install Worker Node"
    echo "4. Join Additional Master Node"
    echo "5. Join Worker Node"
    echo "6. Exit"
    echo
    read -p "Please select an option (1-6): " choice
    echo
    return $choice
}

# Function to generate new join commands from existing master
generate_join_commands() {
    print_color "green" "Generating new join commands for existing cluster..."
    
    # Check if this is actually a master node
    if ! kubectl get nodes &>/dev/null; then
        print_color "red" "Error: Unable to access the cluster. Is this a master node?"
        print_color "red" "Make sure you have valid kubeconfig (/etc/kubernetes/admin.conf)"
        return 1
    fi
    
    # Create directory for join commands if it doesn't exist
    mkdir -p /root/cluster-join
    
    # Generate new bootstrap token
    NEW_TOKEN=$(kubeadm token create)
    
    # Get CA cert hash
    CA_CERT_HASH=$(openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
                   openssl rsa -pubin -outform der 2>/dev/null | \
                   openssl dgst -sha256 -hex | sed 's/^.* //')
    
    # Get API server endpoint
    API_SERVER_IP=$(kubectl get endpoints kubernetes -n default -o jsonpath='{.subsets[0].addresses[0].ip}')
    
    # Generate new certificate key for control plane joins
    CERT_KEY=$(kubeadm init phase upload-certs --upload-certs 2>/dev/null | tail -1)
    
    # Create worker join command
    echo "kubeadm join ${API_SERVER_IP}:6443 --token ${NEW_TOKEN} --discovery-token-ca-cert-hash sha256:${CA_CERT_HASH}" \
         > /root/cluster-join/worker-join.txt
    
    # Create control-plane join command
    echo "kubeadm join ${API_SERVER_IP}:6443 --token ${NEW_TOKEN} --discovery-token-ca-cert-hash sha256:${CA_CERT_HASH} --control-plane --certificate-key ${CERT_KEY}" \
         > /root/cluster-join/control-plane-join.txt
    
    # Save certificate key separately
    echo "$CERT_KEY" > /root/cluster-join/certificate-key.txt
    
    # Secure the files
    chmod 600 /root/cluster-join/*
    
    print_color "green" "Join commands generated successfully!"
    echo "Join commands are saved in /root/cluster-join/"
    echo "- Control plane join command: /root/cluster-join/control-plane-join.txt"
    echo "- Worker join command: /root/cluster-join/worker-join.txt"
    echo "- Certificate key: /root/cluster-join/certificate-key.txt"
    print_color "yellow" "SECURITY NOTE: These files contain sensitive information!"
    echo "Transfer them securely to the new nodes and delete when done."
}

# Function to check cluster health
check_cluster_health() {
    print_color "green" "Checking cluster health..."
    
    # Check node status
    echo "Node Status:"
    kubectl get nodes -o wide
    echo
    
    # Check control plane pods
    echo "Control Plane Components:"
    kubectl get pods -n kube-system -l tier=control-plane
    echo
    
    # Check etcd
    echo "etcd Status:"
    kubectl get pods -n kube-system -l component=etcd
    echo
    
    # Check if CoreDNS is running
    echo "CoreDNS Status:"
    kubectl get pods -n kube-system -l k8s-app=kube-dns
    echo
}

# Function to verify node prerequisites
verify_prerequisites() {
    print_color "green" "Verifying node prerequisites..."
    
    # Check if swap is disabled
    if [[ $(swapon --show) ]]; then
        print_color "red" "Swap is enabled. Must be disabled for Kubernetes"
        return 1
    fi
    
    # Check required kernel modules
    local required_modules=("overlay" "br_netfilter")
    for module in "${required_modules[@]}"; do
        if ! lsmod | grep -q "^$module"; then
            print_color "red" "Required kernel module $module is not loaded"
            return 1
        fi
    done
    
    # Check required sysctl settings
    local required_settings=(
        "net.bridge.bridge-nf-call-iptables"
        "net.bridge.bridge-nf-call-ip6tables"
        "net.ipv4.ip_forward"
    )
    for setting in "${required_settings[@]}"; do
        if [[ $(sysctl -n $setting) != "1" ]]; then
            print_color "red" "Required sysctl setting $setting is not set to 1"
            return 1
        fi
    done
    
    # Check if containerd is running
    if ! systemctl is-active --quiet containerd; then
        print_color "red" "containerd is not running"
        return 1
    fi
    
    # Check if ports are available
    local required_ports=(6443 10250 10259 10257 2379 2380)
    for port in "${required_ports[@]}"; do
        if netstat -tuln | grep -q ":$port "; then
            print_color "red" "Required port $port is already in use"
            return 1
        fi
    done
    
    print_color "green" "All prerequisites verified successfully!"
    return 0
}

# Function to show menu
#!/bin/bash

# ... (Previous helper functions remain the same until show_menu)

# Function to show menu and get selection
show_menu() {
    while true; do
        print_color "blue" "\nKubernetes Cluster Setup Menu"
        echo "1. Install First Master Node"
        echo "2. Install Additional Master Node"
        echo "3. Install Worker Node"
        echo "4. Join Additional Master Node"
        echo "5. Join Worker Node"
        echo "6. Generate New Join Commands (Existing Cluster)"
        echo "7. Check Cluster Health"
        echo "8. Verify Node Prerequisites"
        echo "9. Exit"
        echo
        read -p "Please select an option (1-9): " choice
        
        case $choice in
            1|2|3|4|5|6|7|8|9)
                return "$choice"
                ;;
            *)
                print_color "red" "Invalid option. Please select 1-9"
                sleep 1
                ;;
        esac
    done
}

# Main script execution
main() {
    check_root
    detect_os
    
    while true; do
        show_menu
        choice=$?
        
        case $choice in
            1)  # Install First Master Node
                print_color "green" "Starting First Master Node Installation..."
                read -p "Enter Kubernetes version (e.g., 1.28.0): " K8S_VERSION
                
                if ! validate_k8s_version "$K8S_VERSION"; then
                    print_color "red" "Invalid Kubernetes version format"
                    continue
                fi
                
                read -p "Enter pod network CIDR (default: 192.168.0.0/16): " POD_NETWORK_CIDR
                POD_NETWORK_CIDR=${POD_NETWORK_CIDR:-"192.168.0.0/16"}
                
                read -p "Enter API Server IP (this node's IP): " API_SERVER_IP
                if ! validate_ip "$API_SERVER_IP"; then
                    print_color "red" "Invalid IP address format"
                    continue
                fi
                
                SUDO_USER=${SUDO_USER:-$(whoami)}
                if [ "$SUDO_USER" = "root" ]; then
                    read -p "Enter the name of the non-root user to configure: " SUDO_USER
                    if [ -z "$SUDO_USER" ]; then
                        print_color "red" "Username cannot be empty"
                        continue
                    fi
                fi
                
                print_color "yellow" "Starting installation with following configuration:"
                echo "Kubernetes Version: $K8S_VERSION"
                echo "Pod Network CIDR: $POD_NETWORK_CIDR"
                echo "API Server IP: $API_SERVER_IP"
                echo "User: $SUDO_USER"
                echo
                read -p "Continue with installation? (y/n): " confirm
                if [[ ! $confirm =~ ^[Yy]$ ]]; then
                    print_color "yellow" "Installation cancelled"
                    continue
                fi
                
                setup_prerequisites || { print_color "red" "Prerequisites setup failed"; continue; }
                install_containerd || { print_color "red" "Containerd installation failed"; continue; }
                install_kubernetes_packages "$K8S_VERSION" || { print_color "red" "Kubernetes packages installation failed"; continue; }
                initialize_first_master "$POD_NETWORK_CIDR" "$API_SERVER_IP" || { print_color "red" "Master node initialization failed"; continue; }
                setup_user_permissions "$SUDO_USER" || { print_color "red" "User permissions setup failed"; continue; }
                print_cluster_info "$SUDO_USER" "First Master Node"
                ;;
                
            2)  # Install Additional Master Node
                print_color "green" "Starting Additional Master Node Installation..."
                read -p "Enter Kubernetes version (e.g., 1.28.0): " K8S_VERSION
                
                if ! validate_k8s_version "$K8S_VERSION"; then
                    print_color "red" "Invalid Kubernetes version format"
                    continue
                fi
                
                print_color "yellow" "Starting installation with Kubernetes version: $K8S_VERSION"
                read -p "Continue with installation? (y/n): " confirm
                if [[ ! $confirm =~ ^[Yy]$ ]]; then
                    print_color "yellow" "Installation cancelled"
                    continue
                fi
                
                setup_prerequisites || { print_color "red" "Prerequisites setup failed"; continue; }
                install_containerd || { print_color "red" "Containerd installation failed"; continue; }
                install_kubernetes_packages "$K8S_VERSION" || { print_color "red" "Kubernetes packages installation failed"; continue; }
                print_color "green" "Node prepared for joining as additional control plane node."
                print_color "yellow" "Use option 4 to complete the join process."
                ;;
                
            3)  # Install Worker Node
                print_color "green" "Starting Worker Node Installation..."
                read -p "Enter Kubernetes version (e.g., 1.28.0): " K8S_VERSION
                
                if ! validate_k8s_version "$K8S_VERSION"; then
                    print_color "red" "Invalid Kubernetes version format"
                    continue
                fi
                
                print_color "yellow" "Starting installation with Kubernetes version: $K8S_VERSION"
                read -p "Continue with installation? (y/n): " confirm
                if [[ ! $confirm =~ ^[Yy]$ ]]; then
                    print_color "yellow" "Installation cancelled"
                    continue
                fi
                
                setup_prerequisites || { print_color "red" "Prerequisites setup failed"; continue; }
                install_containerd || { print_color "red" "Containerd installation failed"; continue; }
                install_kubernetes_packages "$K8S_VERSION" || { print_color "red" "Kubernetes packages installation failed"; continue; }
                print_color "green" "Node prepared for joining as worker node."
                print_color "yellow" "Use option 5 to complete the join process."
                ;;
                
            4)  # Join Additional Master Node
                print_color "yellow" "Joining as Additional Control Plane Node..."
                print_color "yellow" "Requirements:"
                echo "1. The control plane join command from the first master node"
                echo "   (Located in /root/control-plane-join.txt on the first master)"
                echo
                read -p "Please paste the full join command: " JOIN_COMMAND
                
                if [ -z "$JOIN_COMMAND" ]; then
                    print_color "red" "Join command cannot be empty"
                    continue
                fi
                
                if [[ ! $JOIN_COMMAND == *"--control-plane"* ]]; then
                    print_color "red" "Invalid control plane join command"
                    continue
                fi
                
                print_color "yellow" "About to execute join command. Continue? (y/n): " confirm
                read -p "" confirm
                if [[ ! $confirm =~ ^[Yy]$ ]]; then
                    print_color "yellow" "Join cancelled"
                    continue
                fi
                
                join_control_plane "$JOIN_COMMAND" || { print_color "red" "Join failed"; continue; }
                print_cluster_info "root" "Additional Master Node"
                ;;
                
            5)  # Join Worker Node
                print_color "yellow" "Joining as Worker Node..."
                print_color "yellow" "Requirements:"
                echo "1. The worker join command from the first master node"
                echo "   (Located in /root/worker-join.txt on the first master)"
                echo
                read -p "Please paste the full join command: " JOIN_COMMAND
                
                if [ -z "$JOIN_COMMAND" ]; then
                    print_color "red" "Join command cannot be empty"
                    continue
                fi
                
                print_color "yellow" "About to execute join command. Continue? (y/n): " confirm
                read -p "" confirm
                if [[ ! $confirm =~ ^[Yy]$ ]]; then
                    print_color "yellow" "Join cancelled"
                    continue
                fi
                
                join_worker "$JOIN_COMMAND" || { print_color "red" "Join failed"; continue; }
                print_cluster_info "root" "Worker Node"
                ;;
                
            6)  # Generate New Join Commands
                print_color "yellow" "Generating New Join Commands for Existing Cluster..."
                print_color "yellow" "Make sure you are running this on an existing master node."
                echo
                read -p "Continue? (y/n): " confirm
                if [[ ! $confirm =~ ^[Yy]$ ]]; then
                    continue
                fi
                
                generate_join_commands || print_color "red" "Failed to generate join commands"
                ;;
                
            7)  # Check Cluster Health
                check_cluster_health || print_color "red" "Cluster health check failed"
                ;;
                
            8)  # Verify Prerequisites
                verify_prerequisites || print_color "red" "Prerequisites verification failed"
                ;;
                
            9)  # Exit
                print_color "green" "Exiting..."
                exit 0
                ;;
                
            *)
                print_color "red" "Invalid option. Please select 1-9"
                ;;
        esac
        
        # Add a pause before showing the menu again
        echo
        read -p "Press Enter to continue..."
    done
}

# Execute main function with any passed arguments
main "$@"


