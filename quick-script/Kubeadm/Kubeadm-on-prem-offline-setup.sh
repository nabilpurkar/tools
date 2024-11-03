#!/bin/bash

K8S_VERSION="1.28.15"
KUBERNETES_REPO_VERSION="${KUBERNETES_REPO_VERSION:-v1.28}"
KUBELET_VERSION="1.28.15-150500.1.1"
KUBEADM_VERSION="1.28.15-150500.1.1"
KUBECTL_VERSION="1.28.15-150500.1.1"
KUBERNETES_PACKAGE_CNI_VERSION="1.2.0"
CRI_PACKAGE_TOOL_VERSION="1.28.0"
CONTAINERD_VERSION="1.7.14"
CNI_VERSION="v1.3.0"
CALICO_VERSION="v3.26.1"
PAUSE_REGISTRY_VERSION="3.9"
ETCD_IMAGE_VERSION=3.5.15-0
CORE_DNS_IMAGE_VERSION=v1.10.1


POD_NETWORK_CIDR="10.0.0.0/16"

BASE_DIR="${HOME}"
PACKAGES_DIR="${BASE_DIR}/packages"


# Create required directories
mkdir -p "${PACKAGES_DIR}"/{docker_rpm,kubeadm,images}


show_menu() {
    clear
    echo -e "\033[1;36m┌────────────────────────────────────────────────────────┐\033[0m"
    echo -e "\033[1;36m│\033[0m               \033[1;33mKubernetes Offline Setup\033[0m                \033[1;36m│\033[0m"
    echo -e "\033[1;36m├────────────────────────────────────────────────────────┤\033[0m"
    echo -e "\033[1;36m│\033[0m                                                        \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m  \033[1;32m1.\033[0m \033[1;37mDownload Required Packages\033[0m                      \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m     \033[1;30m[Internet Required] [Master/Worker]\033[0m                \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m                                                        \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m  \033[1;32m2.\033[0m \033[1;37mSave Kubernetes Images\033[0m                          \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m     \033[1;30m[Internet Required] [Master/Worker]\033[0m                \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m                                                        \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m  \033[1;32m3.\033[0m \033[1;37mTransfer Files\033[0m                                  \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m                                                        \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m  \033[1;32m4.\033[0m \033[1;37mInstall Packages\033[0m                                \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m     \033[1;30m[Master/Worker]\033[0m                                    \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m                                                        \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m  \033[1;32m5.\033[0m \033[1;37mLoad Images\033[0m                                     \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m     \033[1;30m[Master/Worker]\033[0m                                    \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m                                                        \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m  \033[1;32m6.\033[0m \033[1;37mSetup Master Node\033[0m                               \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m                                                        \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m  \033[1;32m7.\033[0m \033[1;37mSetup Worker Node\033[0m                               \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m                                                        \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m  \033[1;32m8.\033[0m \033[1;37mGenerate Join Commands\033[0m                          \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m                                                        \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m  \033[1;31m9.\033[0m \033[1;37mExit\033[0m                                           \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m                                                        \033[1;36m│\033[0m"
    echo -e "\033[1;36m└────────────────────────────────────────────────────────┘\033[0m"
    echo
    echo -e "\033[1;33mPlease enter your choice [1-9]:\033[0m "
}


configure_prerequisites() {
    echo "Configuring system prerequisites..."
    
    # Disable swap
    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    sudo swapoff -a
    
    # Load required modules
    sudo tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF
    
    # Load modules immediately
    sudo modprobe overlay
    sudo modprobe br_netfilter
    
    # Setup required sysctl params
    sudo tee /etc/sysctl.d/kubernetes.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
    
    # Apply sysctl params without reboot
    sudo sysctl --system
}


download_packages() {
    echo "Downloading required packages..."
    
    # Ask for node type
    read -p "Do You Want To Download Packages For (Master/Worker): " NODE_TYPE
    case "${NODE_TYPE,,}" in
        master|worker)
            echo "Downloading packages for ${NODE_TYPE} node..."
            ;;
        *)
            echo "Invalid node type. Please specify 'master' or 'worker'"
            return 1
            ;;
    esac

    # Create necessary directories
    mkdir -p ${PACKAGES_DIR}/{kubeadm,containerd}
    
    # Download containerd
    echo "Downloading containerd..."
    curl -L "https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz" \
        -o "${PACKAGES_DIR}/containerd/containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz"
    
    # Download containerd service file
    echo "Downloading containerd service file..."
    curl -L "https://raw.githubusercontent.com/containerd/containerd/main/containerd.service" \
        -o "${PACKAGES_DIR}/containerd/containerd.service"

    # Download CNI plugins
    echo "Downloading CNI plugins..."
    curl -L "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz" \
        -o "${PACKAGES_DIR}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz"

    # Setup Kubernetes repo for yumdownloader
    echo "Setting up Kubernetes repository..."
    cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${KUBERNETES_REPO_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${KUBERNETES_REPO_VERSION}/rpm/repodata/repomd.xml.key
EOF

    # Clean and update repos
    sudo yum clean all
    sudo yum makecache

    # Download common dependencies including runc
    echo "Downloading common dependencies..."
    sudo yumdownloader --assumeyes --destdir="${PACKAGES_DIR}/kubeadm" --resolve \
        conntrack-tools \
        socat \
        "kubernetes-cni >= ${KUBERNETES_PACKAGE_CNI_VERSION}" \
        "cri-tools >= ${CRI_PACKAGE_TOOL_VERSION}" \
        ebtables \
        ethtool \
        iptables \
        runc

    # Download Kubernetes packages based on node type
    echo "Downloading Kubernetes packages..."
    if [ "${NODE_TYPE,,}" = "master" ]; then
        # Master node packages
        sudo yumdownloader --assumeyes --destdir="${PACKAGES_DIR}/kubeadm" --resolve \
            "kubelet-${KUBELET_VERSION}.$(uname -m)" \
            "kubeadm-${KUBEADM_VERSION}.$(uname -m)" \
            "kubectl-${KUBECTL_VERSION}.$(uname -m)"

        # Download Calico manifest
        echo "Downloading Calico manifest..."
        curl -L "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml" \
            -o "${PACKAGES_DIR}/calico-${CALICO_VERSION}.yaml"
    else
        # Worker node packages
        sudo yumdownloader --assumeyes --destdir="${PACKAGES_DIR}/kubeadm" --resolve \
            "kubelet-${KUBELET_VERSION}.$(uname -m)" \
            "kubeadm-${KUBEADM_VERSION}.$(uname -m)"
    fi
    
    echo "Packages downloaded successfully for ${NODE_TYPE} node!"
}



install_packages() {
    echo "Installing packages..."
    
    # Verify installation directory exists
    if [ -z "$INSTALL_PATH" ]; then
        read -p "Enter the installation packages path: " INSTALL_PATH
        if [ ! -d "$INSTALL_PATH" ]; then
            echo "Error: Directory $INSTALL_PATH does not exist"
            return 1
        fi
    fi
    
    # Ask for node type if not already set
    if [ -z "$NODE_TYPE" ]; then
        read -p "Is this a master or worker node? (master/worker): " NODE_TYPE
        case "${NODE_TYPE,,}" in
            master|worker)
                echo "Installing packages for ${NODE_TYPE} node..."
                ;;
            *)
                echo "Invalid node type. Please specify 'master' or 'worker'"
                return 1
                ;;
        esac
    fi
    
    # Ask for node type if not already set
    if [ -z "$NODE_TYPE" ]; then
        read -p "Is this a master or worker node? (master/worker): " NODE_TYPE
        case "${NODE_TYPE,,}" in
            master|worker)
                echo "Installing packages for ${NODE_TYPE} node..."
                ;;
            *)
                echo "Invalid node type. Please specify 'master' or 'worker'"
                return 1
                ;;
        esac
    fi
    
    configure_prerequisites

    echo "Installing containerd..."
    CONTAINERD_TAR="${INSTALL_PATH}/containerd/containerd-${CONTAINERD_VERSION}-linux-amd64.tar.gz"
    if [ -f "$CONTAINERD_TAR" ]; then
        # Extract containerd to /usr/local/bin instead of just /usr/local
        sudo tar -C /usr/local/bin -xzf "$CONTAINERD_TAR"
        
        # Install containerd service file
        sudo cp "${INSTALL_PATH}/containerd/containerd.service" /usr/lib/systemd/system/
        

        # Ensure runc is installed before configuring containerd
        echo "Installing runc..."
        sudo rpm -Uvh --force --nodeps "${INSTALL_PATH}/kubeadm/runc"*.rpm || {
            echo "Error: Failed to install runc"
            return 1
        }

        # Create symlink for system-wide access
        sudo ln -s /usr/local/bin/containerd /usr/bin/containerd
        # Create default containerd configuration
        sudo mkdir -p /etc/containerd
        sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
        
        # Update containerd configuration to use systemd cgroup driver
        sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
        sudo sed -i "s|registry.k8s.io/pause:3.8|registry.k8s.io/pause:${PAUSE_REGISTRY_VERSION}|g" /etc/containerd/config.toml
        

        
        # Configure and start service
        sudo systemctl daemon-reload
        sudo systemctl enable containerd
        sudo systemctl restart containerd
        sudo systemctl status containerd --no-pager
    else
        echo "Error: Containerd archive not found at $CONTAINERD_TAR"
        return 1
    fi    

    # Install CNI plugins
    echo "Installing CNI plugins..."
    sudo mkdir -p /opt/cni/bin
    sudo tar -xzf ${INSTALL_PATH}/cni-plugins-linux-amd64-${CNI_VERSION}.tgz -C /opt/cni/bin

    # Install Kubernetes components
    echo "Installing Kubernetes components..."
    cd "${INSTALL_PATH}/kubeadm" || return 1

    # Install dependencies first
    echo "Installing dependencies..."
    sudo rpm -Uvh --force --nodeps conntrack-tools*.rpm kubernetes-cni*.rpm cri-tools*.rpm 2>/dev/null || true

    # Install main components based on node type
    if [ "${NODE_TYPE,,}" = "master" ]; then
        for pkg in kubelet-*.rpm kubeadm-*.rpm kubectl-*.rpm; do
            if [ -f "$pkg" ]; then
                sudo rpm -Uvh --force --nodeps "$pkg" || echo "Warning: Failed to install $pkg"
            fi
        done
    else
        for pkg in kubelet-*.rpm kubeadm-*.rpm; do
            if [ -f "$pkg" ]; then
                sudo rpm -Uvh --force --nodeps "$pkg" || echo "Warning: Failed to install $pkg"
            fi
        done
    fi

    # Configure kubelet
    sudo mkdir -p /var/lib/kubelet
    cat <<EOF | sudo tee /var/lib/kubelet/config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
resolvConf: /run/systemd/resolve/resolv.conf
EOF

    # Enable kubelet
    sudo systemctl enable kubelet

    echo "Kubernetes components installed successfully!"
    return 0
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
    # Ask for node type
    echo "Do You Want To Save Images For Master or Worker Node (master/worker)?"
    read -p "Enter your choice (master/worker): " NODE_TYPE
    case "${NODE_TYPE,,}" in
        master|worker)
            echo "Saving images for ${NODE_TYPE} node..."
            ;;
        *)
            echo "Invalid node type. Please specify 'master' or 'worker'"
            return 1
            ;;
    esac
    
    cd "${PACKAGES_DIR}"
    
    # Common images for both master and worker
    common_images=(
        "registry.k8s.io/kube-proxy:v${K8S_VERSION}"

        "registry.k8s.io/pause:${PAUSE_REGISTRY_VERSION}"
    )
    
    # Master-specific images
    master_images=(
        "registry.k8s.io/kube-apiserver:v${K8S_VERSION}"

        "registry.k8s.io/kube-controller-manager:v${K8S_VERSION}"

        "registry.k8s.io/kube-scheduler:v${K8S_VERSION}"

        "registry.k8s.io/etcd:${ETCD_IMAGE_VERSION}"

        "registry.k8s.io/coredns/coredns:${CORE_DNS_IMAGE_VERSION}"

        "docker.io/calico/cni:${CALICO_VERSION}"

        "docker.io/calico/node:${CALICO_VERSION}"

        "docker.io/calico/kube-controllers:${CALICO_VERSION}"
    )

    # Initialize images array with common images
    images=("${common_images[@]}")
    
    # Add master-specific images if this is a master node
    if [ "${NODE_TYPE,,}" = "master" ]; then
        images+=("${master_images[@]}")
        archive_name="k8s-master-images.tar"
    else
        archive_name="k8s-worker-images.tar"
    fi
    
    # Pull images
    echo "Pulling images for ${NODE_TYPE} node..."
    for img in "${images[@]}"; do
        echo "Pulling $img..."
        sudo crictl pull "$img" || {
            echo "Failed to pull $img"
            continue
        }
    done

    # Create a manifest file
    manifest_file="${PACKAGES_DIR}/image_manifest.txt"
    printf "%s\n" "${images[@]}" > "$manifest_file"
    
    # Create directory for individual tars
    mkdir -p "${PACKAGES_DIR}/images"
    
    # Save each image individually
    echo "Saving images..."
    for img in "${images[@]}"; do
        echo "Saving $img..."
        # Create a safe filename from the image name
        safe_name=$(echo "$img" | tr '/:' '_')
        # Export the image
        sudo /usr/local/bin/ctr -n=k8s.io images export "${PACKAGES_DIR}/images/${safe_name}.tar" "$img" || {
            echo "Failed to save $img"
            continue
        }
    done

    # Create final archive
    echo "Creating archive ${archive_name}..."
    tar czf "${archive_name}" -C "${PACKAGES_DIR}" images image_manifest.txt
    
    # Cleanup
    rm -rf "${PACKAGES_DIR}/images"
    
    echo "Successfully saved images to ${archive_name}"
    ls -lh "${archive_name}"
}

load_images() {
    echo "Loading Kubernetes images..."

    # Always ask for installation path first
    read -p "Enter the installation packages path: " INSTALL_PATH
    if [ ! -d "$INSTALL_PATH" ]; then
        echo "Error: Directory $INSTALL_PATH does not exist"
        return 1
    fi

    # Ask for node type
    read -p "Is this a master or worker node? (master/worker): " NODE_TYPE
    case "${NODE_TYPE,,}" in
        master|worker)
            echo "Loading images for ${NODE_TYPE} node..."
            ;;
        *)
            echo "Invalid node type. Please specify 'master' or 'worker'"
            return 1
            ;;
    esac

    # Set archive name based on node type
    local archive_name
    if [ "${NODE_TYPE,,}" = "master" ]; then
        archive_name="${INSTALL_PATH}/k8s-master-images.tar"
    else
        archive_name="${INSTALL_PATH}/k8s-worker-images.tar"
    fi

    # Check for archive
    if [ ! -f "${archive_name}" ]; then
        echo "Error: ${archive_name} not found!"
        return 1
    fi

    # Create temporary directory
    temp_dir=$(mktemp -d)
    trap 'rm -rf "${temp_dir}"' EXIT

    # Extract archive
    echo "Extracting images..."
    tar xzf "${archive_name}" -C "${temp_dir}"

    # Load images
    echo "Loading images..."
    for image_tar in "${temp_dir}"/images/*.tar; do
        echo "Loading ${image_tar}..."
        sudo /usr/local/bin/ctr -n=k8s.io images import "${image_tar}" || {
            echo "Failed to load ${image_tar}"
            continue
        }
    done

    # Verify loaded images
    echo "Verifying loaded images..."
    if [ "${NODE_TYPE,,}" = "master" ]; then
        echo "Master node images:"
        sudo crictl images | grep -E 'k8s.io|calico'
    else
        echo "Worker node images:"
        sudo crictl images | grep -E 'pause|kube-proxy'
    fi
    
    echo "Images loaded successfully for ${NODE_TYPE} node!"
    return 0
}

setup_master() {
    echo "Setting up master node..."
    configure_prerequisites
    
    # Ask user for initialization choice
    echo "=============================="
    echo "Choose master node setup type:"
    echo "1. Initialize new cluster (Online)"
    echo "2. Join existing cluster as control plane"
    echo "3. Initialize new cluster (Offline)"
    echo "=============================="
    read -p "Enter your choice [1-3]: " master_choice
    

    case $master_choice in
        1)
            echo "Initializing new Kubernetes cluster (Online mode)..."
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
        3)
            echo "Initializing new Kubernetes cluster (Offline mode)..."
            read -p "Enter the API server IP address: " API_SERVER_IP
            
            # Verify required images are present (base names only)
            echo "Verifying required images..."
            missing_images=0
            
            # Check core K8s images
            for image in "kube-apiserver" "kube-controller-manager" "kube-scheduler" "kube-proxy" "pause" "etcd" "coredns"; do
                if ! sudo crictl image ls | grep -q "$image"; then
                    echo "Missing required image: $image"
                    missing_images=1
                fi
            done

            if [ $missing_images -eq 1 ]; then
                echo "Error: Some required images are missing. Please load all required images first."
                return 1
            fi

            echo "All required images found. Proceeding with offline installation..."
            
            # Initialize the cluster with corrected flags
            if sudo kubeadm init \
                --apiserver-advertise-address=${API_SERVER_IP} \
                --pod-network-cidr=${POD_NETWORK_CIDR} \
                --kubernetes-version=${K8S_VERSION} \
                --ignore-preflight-errors=SystemVerification \
                --cri-socket unix:///var/run/containerd/containerd.sock \
                --v=5; then

                
                # Wait for admin.conf to be created
                echo "Waiting for admin.conf to be created..."
                for i in {1..30}; do
                    if [ -f /etc/kubernetes/admin.conf ]; then
                        break
                    fi
                    sleep 2
                done

                # Setup kubeconfig for the user
                echo "Setting up kubeconfig..."
                mkdir -p $HOME/.kube
                if [ -f /etc/kubernetes/admin.conf ]; then
                    sudo chmod 600 /etc/kubernetes/admin.conf
                    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
                    sudo chown $(id -u):$(id -g) $HOME/.kube/config
                    echo "Kubeconfig setup completed successfully"
                    sudo chmod 600 $HOME/.kube/config
                else
                    echo "Warning: admin.conf not found. You may need to manually set up kubeconfig"
                fi
            else
                echo "Failed to initialize Kubernetes cluster"
                return 1
            fi
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
        kubectl apply -f $INSTALL_PATH/calico-${CALICO_VERSION}.yaml
    fi
    
    echo "Master node setup completed!"
}

setup_worker() {
    echo "Setting up worker node..."
    configure_prerequisites
        
    read -p "Enter the kubeadm join command from master: " JOIN_CMD
    sudo $JOIN_CMD
    
    echo "Worker node setup completed!"
}

# Function to generate new join commands from existing master
generate_join_commands() {
    echo "Generating new join commands for existing cluster..."
    
    # Check if this is actually a master node
    if ! kubectl get nodes &>/dev/null; then
        echo "Error: Unable to access the cluster. Is this a master node?"
        echo "Make sure you have valid kubeconfig (/etc/kubernetes/admin.conf)"
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
    echo "kubeadm join ${API_SERVER_IP}:6443 --token ${NEW_TOKEN} --discovery-token-ca-cert-hash sha256:${CA_CERT_HASH}" > /root/cluster-join/worker-join.txt
    
    # Create control-plane join command
    echo "kubeadm join ${API_SERVER_IP}:6443 --token ${NEW_TOKEN} --discovery-token-ca-cert-hash sha256:${CA_CERT_HASH} --control-plane --certificate-key ${CERT_KEY}" > /root/cluster-join/control-plane-join.txt
    
    # Save certificate key separately
    echo "${CERT_KEY}" > /root/cluster-join/certificate-key.txt
    
    # Secure the files
    chmod 600 /root/cluster-join/*
    
    echo "Join commands generated successfully!"
    echo "Join commands are saved in /root/cluster-join/"
    echo "- Control plane join command: /root/cluster-join/control-plane-join.txt"
    echo "- Worker join command: /root/cluster-join/worker-join.txt"
    echo "- Certificate key: /root/cluster-join/certificate-key.txt"
    echo "SECURITY NOTE: These files contain sensitive information!"
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
