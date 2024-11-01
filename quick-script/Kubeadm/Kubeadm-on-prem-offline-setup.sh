#!/bin/bash

K8S_VERSION="1.28.15"
CALICO_VERSION="v3.26.1"
BASE_DIR="${HOME}"
PACKAGES_DIR="${BASE_DIR}/packages"

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
    wget https://github.com/containerd/containerd/releases/download/v1.7.14/containerd-1.7.14-linux-amd64.tar.gz -P ${PACKAGES_DIR}

    # Download CNI plugins
    wget https://github.com/containernetworking/plugins/releases/download/v1.3.0/cni-plugins-linux-amd64-v1.3.0.tgz -P ${PACKAGES_DIR}

    # Setup Kubernetes repo
    cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
EOF

    # Download Kubernetes packages
    sudo yum clean all
    sudo yum makecache
    
    sudo yumdownloader --assumeyes --destdir=${PACKAGES_DIR}/kubeadm --resolve \
        kubelet-1.28.15-150500.1.1.$(uname -m) \
        kubeadm-1.28.15-150500.1.1.$(uname -m) \
        kubectl-1.28.15-150500.1.1.$(uname -m) \
        ebtables

    # Download Calico manifest
    wget https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml -P ${PACKAGES_DIR}
    
    echo "Packages downloaded successfully!"
}

install_packages() {
    echo "Installing packages..."
    
    # Install Docker packages
    sudo yum install -y --cacheonly --disablerepo=* ${PACKAGES_DIR}/docker_rpm/yum/*.rpm
    sudo yum install -y --cacheonly --disablerepo=* ${PACKAGES_DIR}/docker_rpm/dm/*.rpm
    sudo yum install -y --cacheonly --disablerepo=* ${PACKAGES_DIR}/docker_rpm/lvm2/*.rpm
    sudo yum install -y --cacheonly --disablerepo=* ${PACKAGES_DIR}/docker_rpm/se/*.rpm
    sudo yum install -y --cacheonly --disablerepo=* ${PACKAGES_DIR}/docker_rpm/docker-ce/*.rpm

    # Install containerd
    sudo tar Cxzvf /usr/local ${PACKAGES_DIR}/containerd-1.7.14-linux-amd64.tar.gz
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
    sudo systemctl start containerd

    # Install CNI plugins
    sudo mkdir -p /opt/cni/bin
    sudo tar -xzf ${PACKAGES_DIR}/cni-plugins-linux-amd64-v1.3.0.tgz -C /opt/cni/bin

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
    
    # Disable swap
    sudo swapoff -a
    
    
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
            sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --kubernetes-version=${K8S_VERSION}
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
        mkdir -p $HOME/.kube
        sudo rm -f $HOME/.kube/config
        sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
        sudo chown $(id -u):$(id -g) $HOME/.kube/config
        chmod 600 $HOME/.kube/config
            
        # Export KUBECONFIG
        export KUBECONFIG=$HOME/.kube/config
    
    # Apply Calico network (only for init, not join)
    if [ "$master_choice" == "1" ]; then
        echo "Applying Calico network..."
        kubectl apply -f ${PACKAGES_DIR}/calico.yaml
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

generate_join_commands() {
    echo "Generating join commands..."
    echo "Control plane join command:"
    kubeadm token create --print-join-command
    echo -e "\nTo get certificate key for control plane:"
    kubeadm init phase upload-certs --upload-certs
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
