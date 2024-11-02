#!/bin/bash

K8S_VERSION="1.28.15"
KUBERNETES_REPO_VERSION="${KUBERNETES_REPO_VERSION:-v1.28}"
KUBELET_VERSION="1.28.15-150500.1.1"
KUBEADM_VERSION="1.28.15-150500.1.1"
KUBECTL_VERSION="1.28.15-150500.1.1"
POD_NETWORK_CIDR="10.244.0.0/16"

CALICO_VERSION="v3.26.1"
BASE_DIR="${HOME}"
PACKAGES_DIR="${BASE_DIR}/packages"
CONTAINERD_VERSION="1.7.14"
CNI_VERSION="v1.3.0"

# Create required directories
mkdir -p "${PACKAGES_DIR}"/{docker_rpm,kubeadm,images}

# Function to check container runtime
check_container_runtime() {
    if command -v docker &> /dev/null; then
        echo "docker"
    elif command -v podman &> /dev/null; then
        echo "podman"
    else
        echo "none"
    fi
}

show_menu() {
    clear
    echo "==================================="
    echo "Kubernetes Offline Setup Menu"
    echo "==================================="
    echo "1. Download Required Packages (Master)"
    echo "2. Save Kubernetes Images (Master)"
    echo "3. Transfer Files to Worker Node"
    echo "4. Install Packages (Worker/Master)"
    echo "5. Load Images (Worker/Master)"
    echo "6. Setup Master Node"
    echo "7. Setup Worker Node"
    echo "8. Generate Join Commands"
    echo "9. Exit"
    echo "==================================="
}

download_packages() {
    echo "Downloading required packages..."
    
    # Docker packages
    sudo yum install -y yum-utils
    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    
    # Download Docker dependencies
    sudo yumdownloader --assumeyes --destdir=${PACKAGES_DIR}/docker_rpm/yum --resolve yum-utils
    sudo yumdownloader --assumeyes --destdir=${PACKAGES_DIR}/docker_rpm/dm --resolve device-mapper-persistent-data
    sudo yumdownloader --assumeyes --destdir=${PACKAGES_DIR}/docker_rpm/lvm2 --resolve lvm2
    sudo yumdownloader --assumeyes --destdir=${PACKAGES_DIR}/docker_rpm/docker-ce --resolve docker-ce
    sudo yumdownloader --assumeyes --destdir=${PACKAGES_DIR}/docker_rpm/se --resolve container-selinux



    # Download containerd
    curl -L "https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz" \
        -o "${PACKAGES_DIR}/containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz"

    # Download CNI plugins
    curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz" \
        -o "${PACKAGES_DIR}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz"


    # Setup Kubernetes repo
    cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${KUBERNETES_REPO_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${KUBERNETES_REPO_VERSION}/rpm/repodata/repomd.xml.key
EOF

    # Download Kubernetes packages
    sudo yum clean all
    sudo yum makecache
    

    sudo yumdownloader --assumeyes --destdir="${PACKAGES_DIR}/kubeadm" --resolve \
    "kubelet-${KUBELET_VERSION}.$(uname -m)" \
    "kubeadm-${KUBEADM_VERSION}.$(uname -m)" \
    "kubectl-${KUBECTL_VERSION}.$(uname -m)" \
        ebtables

    # Download Calico manifest
    curl -L "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml" \
        -o "${PACKAGES_DIR}/calico-${CALICO_VERSION}.yaml"
    
    echo "Packages downloaded successfully!"
}

install_packages() {
    echo "Installing packages..."
    
    # Install Docker packages
    echo "Docker packages..."
    sudo yum install -y --cacheonly --disablerepo=* ${PACKAGES_DIR}/docker_rpm/yum/*.rpm
    sudo yum install -y --cacheonly --disablerepo=* ${PACKAGES_DIR}/docker_rpm/dm/*.rpm
    sudo yum install -y --cacheonly --disablerepo=* ${PACKAGES_DIR}/docker_rpm/lvm2/*.rpm
    sudo yum install -y --cacheonly --disablerepo=* ${PACKAGES_DIR}/docker_rpm/se/*.rpm
    sudo yum install -y --cacheonly --disablerepo=* ${PACKAGES_DIR}/docker_rpm/docker-ce/*.rpm

    # Start Docker
    echo "Starting Docker"
    sudo systemctl enable docker
    sudo systemctl start docker
    sudo usermod -aG docker $USER

    # Install containerd
    echo "Install containerd"
    sudo tar -xzf ${PACKAGES_DIR}/containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz -C /usr/local/bin/
    sudo mkdir -p /etc/containerd
    sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

    # Configure system for containerd
    sudo modprobe br_netfilter
    sudo mkdir -p /proc/sys/net/bridge
    sudo bash -c 'echo "1" > /proc/sys/net/bridge/bridge-nf-call-iptables'
    sudo bash -c 'echo "1" > /proc/sys/net/bridge/bridge-nf-call-ip6tables'
    sudo bash -c 'echo "1" > /proc/sys/net/ipv4/ip_forward'
    
    # Make network settings persistent
    sudo bash -c 'cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF'

    sudo sysctl --system

    # Start containerd
    sudo systemctl enable containerd
    sudo systemctl restart containerd


    # Install CNI plugins
    sudo mkdir -p /opt/cni/bin
    sudo tar -xzf ${PACKAGES_DIR}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz -C /opt/cni/bin

    # Install Kubernetes packages
    sudo yum install -y --cacheonly --disablerepo=* ${PACKAGES_DIR}/kubeadm/*.rpm --allowerasing --skip-broken
    sudo systemctl enable kubelet.service

    echo "Packages installed successfully!"
}


check_container_runtime() {
    if command -v docker &> /dev/null; then
        echo "docker"
    elif command -v podman &> /dev/null; then
        echo "podman"
    else
        echo "none"
    fi
}


transfer_files() {
    echo "==================================="
    echo "File Transfer Configuration"
    echo "==================================="
    read -p "Enter worker node IP: " WORKER_IP
    read -p "Enter worker node username: " WORKER_USER
    
    echo -e "\nSelect authentication method:"
    echo "1. SSH Key"
    echo "2. Password"
    read -p "Enter your choice [1-2]: " AUTH_METHOD
    
    case $AUTH_METHOD in
        1)
            echo -e "\nUsing SSH Key authentication"
            read -p "Enter path to SSH private key [default: ~/.ssh/id_rsa]: " SSH_KEY
            SSH_KEY=${SSH_KEY:-~/.ssh/id_rsa}
            
            if [ ! -f "$SSH_KEY" ]; then
                echo "Error: SSH key file not found: $SSH_KEY"
                return 1
            fi
            
            echo "Transferring files to worker node..."
            if scp -i "$SSH_KEY" -o ConnectTimeout=10 -r ${PACKAGES_DIR} ${WORKER_USER}@${WORKER_IP}:~/; then
                echo "Files transferred successfully!"
            else
                echo "Error: File transfer failed using SSH key"
                return 1
            fi
            ;;
            
        2)
            echo -e "\nUsing Password authentication"
            # Check if sshpass is installed
            if ! command -v sshpass &> /dev/null; then
                echo "sshpass is not installed. Installing..."
                sudo yum install -y sshpass || sudo apt-get install -y sshpass
            fi
            
            # Prompt for password securely
            read -s -p "Enter password for $WORKER_USER@$WORKER_IP: " WORKER_PASS
            echo
            
            echo "Transferring files to worker node..."
            if SSHPASS="$WORKER_PASS" sshpass -e scp -o StrictHostKeyChecking=no -r ${PACKAGES_DIR} ${WORKER_USER}@${WORKER_IP}:~/; then
                echo "Files transferred successfully!"
            else
                echo "Error: File transfer failed using password"
                return 1
            fi
            ;;
            
        *)
            echo "Invalid authentication method selected"
            return 1
            ;;
    esac
    
    # Verify transfer by checking file existence
    echo -e "\nVerifying file transfer..."
    if [ "$AUTH_METHOD" = "1" ]; then
        if ssh -i "$SSH_KEY" ${WORKER_USER}@${WORKER_IP} "test -d ~/packages"; then
            echo "Verification successful: Files exist on remote node"
        else
            echo "Warning: Could not verify files on remote node"
        fi
    else
        if SSHPASS="$WORKER_PASS" sshpass -e ssh -o StrictHostKeyChecking=no ${WORKER_USER}@${WORKER_IP} "test -d ~/packages"; then
            echo "Verification successful: Files exist on remote node"
        else
            echo "Warning: Could not verify files on remote node"
        fi
    fi
}



save_images() {
    echo "Saving Kubernetes images..."
    cd "${PACKAGES_DIR}"
    
    # List of images
    images=(
        "registry.k8s.io/kube-apiserver:v${K8S_VERSION}"
        "registry.k8s.io/kube-controller-manager:v${K8S_VERSION}"
        "registry.k8s.io/kube-scheduler:v${K8S_VERSION}"
        "registry.k8s.io/kube-proxy:v${K8S_VERSION}"
        "registry.k8s.io/pause:3.9"
        "registry.k8s.io/etcd:3.5.9-0"
        "registry.k8s.io/coredns/coredns:v1.10.1"
        "docker.io/calico/cni:${CALICO_VERSION}"
        "docker.io/calico/node:${CALICO_VERSION}"
        "docker.io/calico/kube-controllers:${CALICO_VERSION}"
    )
    
    # Pull images first
    for img in "${images[@]}"; do
        echo "Pulling $img..."
        sudo docker pull "$img" || {
            echo "Failed to pull $img"
            continue
        }
    done

    # Save all images in a single archive
    echo "Saving images..."
    image_list=""
    for img in "${images[@]}"; do
        image_list+=" $img"
    done
    
    # Create single uncompressed tar archive
    echo "Creating archive..."
    sudo docker save ${image_list} -o k8s-images.tar

    echo "Successfully saved images to k8s-images.tar"
    ls -lh k8s-images.tar
}

load_images() {
    echo "Loading Kubernetes images..."

    # Debug: Print current directory
    echo "Current directory: $(pwd)"
    
    # Debug: Check if PACKAGES_DIR is set
    echo "PACKAGES_DIR value: ${PACKAGES_DIR}"
    
    ls -ltr -h "${PACKAGES_DIR}"

    # Change directory with verification
    cd "${PACKAGES_DIR}" || {
        echo "Failed to change to directory: ${PACKAGES_DIR}"
        return 1
    }

    # Check for archive
    if [ ! -f "k8s-images.tar" ]; then
        echo "Error: k8s-images.tar not found!"
        return 1
    fi

    # Load images directly
    echo "Loading images..."
    sudo docker load -i /home/ec2-user/packages/k8s-images.tar

    echo "Verifying loaded images..."
    sudo docker images | grep -E 'k8s.io|calico'
}



setup_master() {
    echo "Setting up master node..."
    
    # Configure system settings
    sudo setenforce 0
    sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF

    sudo sysctl --system
    
    
    # Ask user for initialization choice
    echo "=============================="
    echo "Choose master node setup type:"
    echo "1. Initialize new cluster"
    echo "2. Join existing cluster as control plane"
    echo "=============================="
    read -p "Enter your choice [1-2]: " master_choice
    

    case $master_choice in
        1)
            echo "Initializing new Kubernetes cluster..."
            read -p "Enter the API server IP address: " API_SERVER_IP
            sudo kubeadm init \
                --pod-network-cidr=${POD_NETWORK_CIDR} \
                --kubernetes-version=${K8S_VERSION} \
                --apiserver-advertise-address=${API_SERVER_IP} \
                --control-plane-endpoint=${API_SERVER_IP}
            ;;
        2)
            echo "Please enter the join command for control plane (includes --control-plane flag):"
            read -p "Join command: " join_command
            eval sudo $join_command
            ;;
        *)
            echo "Invalid choice. Exiting setup."
            return 1
            ;;
    esac
    

        # Setup kubeconfig with proper permissions
        # Setup for current user
        mkdir -p $HOME/.kube
        sudo rm -f $HOME/.kube/config
        sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
        sudo chown $(id -u):$(id -g) $HOME/.kube/config
        chmod 600 $HOME/.kube/config

        # Setup for root user
        sudo mkdir -p /root/.kube
        sudo cp /etc/kubernetes/admin.conf /root/.kube/config
        sudo chmod 600 /root/.kube/config
            
        # Export KUBECONFIG
        export KUBECONFIG=$HOME/.kube/config
    
    # Apply Calico network (only for init, not join)
    if [ "$master_choice" == "1" ]; then
        echo "Applying Calico network..."
        kubectl apply -f ${PACKAGES_DIR}/calico-${CALICO_VERSION}.yaml
    fi
    
    echo "Master node setup completed!"
}

setup_worker() {
    echo "Setting up worker node..."
    
    # Disable swap
    sudo swapoff -a
    
    # Configure system settings
    sudo setenforce 0
    sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
    
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
    
    sudo sysctl --system
    
    read -p "Enter the kubeadm join command from master: " JOIN_CMD
    sudo $JOIN_CMD
    
    echo "Worker node setup completed!"
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


# Main loop
while true; do
    show_menu
    read -p "Enter your choice [1-9]: " choice
    
    case $choice in
        1) download_packages ;;
        2) save_images ;;
        3) transfer_files ;;
        4) install_packages ;;
        5) load_images ;;
        6) setup_master ;;
        7) setup_worker ;;
        8) generate_join_commands ;;
        9) echo "Exiting..."; exit 0 ;;
        *) echo "Invalid option. Press any key to continue..."; read -n 1 ;;
    esac
    
    echo
    read -p "Press enter to continue..."
done
