#!/bin/bash

# Version variables for upgrade
UPGRADE_K8S_VERSION="1.29.2"
UPGRADE_KUBERNETES_REPO_VERSION="${UPGRADE_KUBERNETES_REPO_VERSION:-v1.29}"
UPGRADE_KUBELET_VERSION="1.29.2-150500.1.1"
UPGRADE_KUBEADM_VERSION="1.29.2-150500.1.1"
UPGRADE_KUBECTL_VERSION="1.29.2-150500.1.1"
UPGRADE_KUBERNETES_PACKAGE_CNI_VERSION="1.2.0"
UPGRADE_CRI_PACKAGE_TOOL_VERSION="1.29.0"
UPGRADE_CONTAINERD_VERSION="1.7.14"
UPGRADE_CNI_VERSION="v1.3.0"
UPGRADE_CALICO_VERSION="v3.27.2"
UPGRADE_PAUSE_REGISTRY_VERSION="3.9"
UPGRADE_ETCD_IMAGE_VERSION="3.5.10-0"
UPGRADE_CORE_DNS_IMAGE_VERSION="v1.11.1"

# Directory structure
UPGRADE_BASE_DIR="${HOME}/k8s_upgrade"
UPGRADE_PACKAGES_DIR="${UPGRADE_BASE_DIR}/packages"

# Create required directories
mkdir -p "${UPGRADE_PACKAGES_DIR}"/{kubeadm,images}

show_upgrade_menu() {
    clear
    echo -e "\033[1;36m┌────────────────────────────────────────────────────────┐\033[0m"
    echo -e "\033[1;36m│\033[0m               \033[1;33mKubernetes Offline Upgrade\033[0m               \033[1;36m│\033[0m"
    echo -e "\033[1;36m├────────────────────────────────────────────────────────┤\033[0m"
    echo -e "\033[1;36m│\033[0m                                                        \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m  \033[1;32m1.\033[0m \033[1;37mDownload Upgrade Packages\033[0m                      \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m     \033[1;30m[Internet Required] [Master/Worker]\033[0m                \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m                                                        \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m  \033[1;32m2.\033[0m \033[1;37mSave Upgrade Images\033[0m                           \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m     \033[1;30m[Internet Required] [Master/Worker]\033[0m                \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m                                                        \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m  \033[1;32m3.\033[0m \033[1;37mTransfer Files\033[0m                                  \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m                                                        \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m  \033[1;32m4.\033[0m \033[1;37mLoad Upgrade Images\033[0m                        \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m     \033[1;30m[Offline] [Master/Worker]\033[0m                \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m                                                        \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m  \033[1;32m5.\033[0m \033[1;37mUpgrade Master Node\033[0m                           \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m                                                        \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m  \033[1;32m6.\033[0m \033[1;37mUpgrade Worker Node\033[0m                           \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m                                                        \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m  \033[1;31m7.\033[0m \033[1;37mExit\033[0m                                         \033[1;36m│\033[0m"
    echo -e "\033[1;36m│\033[0m                                                        \033[1;36m│\033[0m"
    echo -e "\033[1;36m└────────────────────────────────────────────────────────┘\033[0m"
    echo
    echo -e "\033[1;33mPlease enter your choice [1-6]:\033[0m "
}

download_upgrade_packages() {
    echo "Downloading upgrade packages..."
    
    read -p "Do You Want To Download Upgrade Packages For (Master/Worker): " UPGRADE_NODE_TYPE
    case "${UPGRADE_NODE_TYPE,,}" in
        master|worker)
            echo "Downloading upgrade packages for ${UPGRADE_NODE_TYPE} node..."
            ;;
        *)
            echo "Invalid node type. Please specify 'master' or 'worker'"
            return 1
            ;;
    esac

    # Create necessary directories
    mkdir -p ${UPGRADE_PACKAGES_DIR}/{kubeadm,containerd}
    
    # Setup Kubernetes repo for yumdownloader
    echo "Setting up Kubernetes repository..."
    cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${UPGRADE_KUBERNETES_REPO_VERSION}/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${UPGRADE_KUBERNETES_REPO_VERSION}/rpm/repodata/repomd.xml.key
EOF

    # Clean and update repos
    sudo yum clean all
    sudo yum makecache

    # Download all required dependencies first
    echo "Downloading dependencies..."
    sudo yumdownloader --assumeyes --destdir="${UPGRADE_PACKAGES_DIR}/kubeadm" --resolve \
        socat \
        conntrack-tools \
        "kubernetes-cni >= ${UPGRADE_KUBERNETES_PACKAGE_CNI_VERSION}" \
        "cri-tools >= ${UPGRADE_CRI_PACKAGE_TOOL_VERSION}" \
        ebtables \
        ethtool \
        iptables \
        iproute-tc \
        ipvsadm

    # Download Kubernetes packages based on node type
    echo "Downloading Kubernetes upgrade packages..."
    if [ "${UPGRADE_NODE_TYPE,,}" = "master" ]; then
        sudo yumdownloader --assumeyes --destdir="${UPGRADE_PACKAGES_DIR}/kubeadm" --resolve \
            "kubelet-${UPGRADE_KUBELET_VERSION}.$(uname -m)" \
            "kubeadm-${UPGRADE_KUBEADM_VERSION}.$(uname -m)" \
            "kubectl-${UPGRADE_KUBECTL_VERSION}.$(uname -m)"

        # Download new Calico manifest
        echo "Downloading updated Calico manifest..."
        curl -L "https://raw.githubusercontent.com/projectcalico/calico/${UPGRADE_CALICO_VERSION}/manifests/calico.yaml" \
            -o "${UPGRADE_PACKAGES_DIR}/calico-${UPGRADE_CALICO_VERSION}.yaml"
    else
        sudo yumdownloader --assumeyes --destdir="${UPGRADE_PACKAGES_DIR}/kubeadm" --resolve \
            "kubelet-${UPGRADE_KUBELET_VERSION}.$(uname -m)" \
            "kubeadm-${UPGRADE_KUBEADM_VERSION}.$(uname -m)"
    fi
    
    echo "Upgrade packages downloaded successfully for ${UPGRADE_NODE_TYPE} node!"
}


save_upgrade_images() {
    echo "Saving Kubernetes upgrade images..."
    
    read -p "Enter node type for upgrade images (master/worker): " UPGRADE_NODE_TYPE
    case "${UPGRADE_NODE_TYPE,,}" in
        master|worker)
            echo "Saving upgrade images for ${UPGRADE_NODE_TYPE} node..."
            ;;
        *)
            echo "Invalid node type. Please specify 'master' or 'worker'"
            return 1
            ;;
    esac
    
    cd "${UPGRADE_PACKAGES_DIR}"
    
    # Common images for both master and worker upgrade
    upgrade_common_images=(
        "registry.k8s.io/kube-proxy:v${UPGRADE_K8S_VERSION}"
        "registry.k8s.io/pause:${UPGRADE_PAUSE_REGISTRY_VERSION}"
        "registry.k8s.io/coredns/coredns:${UPGRADE_CORE_DNS_IMAGE_VERSION}"
    )
    
    # Master-specific upgrade images
    upgrade_master_images=(
        "registry.k8s.io/kube-apiserver:v${UPGRADE_K8S_VERSION}"
        "registry.k8s.io/kube-controller-manager:v${UPGRADE_K8S_VERSION}"
        "registry.k8s.io/kube-scheduler:v${UPGRADE_K8S_VERSION}"
        "registry.k8s.io/etcd:${UPGRADE_ETCD_IMAGE_VERSION}"
        "registry.k8s.io/coredns/coredns:${UPGRADE_CORE_DNS_IMAGE_VERSION}"
        "docker.io/calico/cni:${UPGRADE_CALICO_VERSION}"
        "docker.io/calico/node:${UPGRADE_CALICO_VERSION}"
        "docker.io/calico/kube-controllers:${UPGRADE_CALICO_VERSION}"
    )

    # Initialize images array with common images
    upgrade_images=("${upgrade_common_images[@]}")
    
    # Add master-specific images if this is a master node
    if [ "${UPGRADE_NODE_TYPE,,}" = "master" ]; then
        upgrade_images+=("${upgrade_master_images[@]}")
        upgrade_archive_name="k8s-master-upgrade-images.tar"
    else
        upgrade_archive_name="k8s-worker-upgrade-images.tar"
    fi
    
    # Pull images
    echo "Pulling upgrade images..."
    for img in "${upgrade_images[@]}"; do
        echo "Pulling $img..."
        sudo crictl pull "$img" || {
            echo "Failed to pull $img"
            continue
        }
    done

    # Save manifest
    printf "%s\n" "${upgrade_images[@]}" > "${UPGRADE_PACKAGES_DIR}/upgrade_image_manifest.txt"
    
    # Create directory for individual tars
    mkdir -p "${UPGRADE_PACKAGES_DIR}/images"
    
    # Save each image
    for img in "${upgrade_images[@]}"; do
        echo "Saving $img..."
        safe_name=$(echo "$img" | tr '/:' '_')
        sudo /usr/local/bin/ctr -n=k8s.io images export "${UPGRADE_PACKAGES_DIR}/images/${safe_name}.tar" "$img" || {
            echo "Failed to save $img"
            continue
        }
    done

    # Create archive
    tar czf "${upgrade_archive_name}" -C "${UPGRADE_PACKAGES_DIR}" images upgrade_image_manifest.txt
    rm -rf "${UPGRADE_PACKAGES_DIR}/images"
    
    echo "Successfully saved upgrade images to ${upgrade_archive_name}"
    ls -lh "${upgrade_archive_name}"
}

load_upgrade_images() {
    echo "Loading Kubernetes upgrade images..."

    # Validate inputs
    read -p "Enter the base upgrade path (path containing the tar files): " UPGRADE_PATH
    if [[ ! -d "${UPGRADE_PATH}" ]]; then
        echo "Error: Directory ${UPGRADE_PATH} does not exist"
        return 1
    fi

    read -p "Is this a master or worker node? (master/worker): " UPGRADE_NODE_TYPE
    case "${UPGRADE_NODE_TYPE,,}" in
        master)
            upgrade_archive_name="${UPGRADE_PATH}/k8s-master-upgrade-images.tar"
            echo "Looking for master node image archive: k8s-master-upgrade-images.tar"
            ;;
        worker)
            upgrade_archive_name="${UPGRADE_PATH}/k8s-worker-upgrade-images.tar"
            echo "Looking for worker node image archive: k8s-worker-upgrade-images.tar"
            ;;
        *)
            echo "Invalid node type. Please specify 'master' or 'worker'"
            return 1
            ;;
    esac

    # Validate archive
    if [[ ! -f "${upgrade_archive_name}" ]]; then
        echo "Error: Image archive not found at ${upgrade_archive_name}"
        return 1
    fi

    # Setup temporary directory
    temp_dir=$(mktemp -d)
    trap 'rm -rf "${temp_dir}"' EXIT

    # Extract archive
    echo "Extracting upgrade images archive..."
    if ! tar xf "${upgrade_archive_name}" -C "${temp_dir}"; then
        echo "Failed to extract image archive"
        return 1
    fi

    # Validate manifest
    if [[ ! -f "${temp_dir}/upgrade_image_manifest.txt" ]]; then
        echo "Error: Image manifest not found in archive"
        return 1
    fi

    # Display manifest
    echo "Reading image manifest..."
    echo "Images to be loaded:"
    cat "${temp_dir}/upgrade_image_manifest.txt"
    echo

    # Check containerd
    if ! command -v ctr &> /dev/null; then
        if [[ -f "/usr/local/bin/ctr" ]]; then
            echo "Creating symlink for ctr command..."
            sudo ln -sf /usr/local/bin/ctr /usr/bin/ctr
        else
            echo "Error: ctr command not found. Please ensure containerd is properly installed"
            return 1
        fi
    fi

    # Check containerd service
    if ! systemctl is-active --quiet containerd; then
        echo "Warning: containerd service is not running. Attempting to start..."
        if ! sudo systemctl start containerd; then
            echo "Error: Failed to start containerd service"
            return 1
        fi
    fi

    # Load images
    echo "Loading images..."
    load_errors=0
    total_images=0
    
    while IFS= read -r image_name; do
        ((total_images++))
        image_file="${temp_dir}/images/$(echo "${image_name}" | tr '/:' '_').tar"
        
        if [[ -f "${image_file}" ]]; then
            echo "Loading image (${total_images}): ${image_name}"
            if ! sudo ctr -n=k8s.io images import "${image_file}"; then
                echo "Warning: Failed to load image: ${image_name}"
                ((load_errors++))
            fi
        else
            echo "Warning: Image file not found: ${image_file}"
            ((load_errors++))
        fi
    done < "${temp_dir}/upgrade_image_manifest.txt"

    # Verify loaded images
    echo -e "\nVerifying loaded images..."
    missing_images=0
    
    while IFS= read -r expected_image; do
        echo -n "Checking image: ${expected_image} ... "
        if sudo crictl inspecti "${expected_image}" >/dev/null 2>&1; then
            echo "OK"
        else
            echo "MISSING"
            ((missing_images++))
        fi
    done < "${temp_dir}/upgrade_image_manifest.txt"

    # Summary
    echo -e "\nImage Loading Summary:"
    echo "Total images processed: ${total_images}"
    echo "Load errors encountered: ${load_errors}"
    echo "Missing images after verification: ${missing_images}"

    if [[ ${load_errors} -eq 0 ]] && [[ ${missing_images} -eq 0 ]]; then
        echo -e "\nAll upgrade images loaded successfully!"
        
        # List loaded images
        echo -e "\nVerifying loaded images for ${UPGRADE_NODE_TYPE} node:"
        case "${UPGRADE_NODE_TYPE,,}" in
            master)
                echo "Control plane images:"
                sudo crictl images | grep -E "v${UPGRADE_K8S_VERSION}|${UPGRADE_ETCD_IMAGE_VERSION}|${UPGRADE_CORE_DNS_IMAGE_VERSION}|${UPGRADE_CALICO_VERSION}"
                ;;
            worker)
                echo "Worker node images:"
                sudo crictl images | grep -E "kube-proxy|pause"
                ;;
        esac
        return 0
    else
        echo -e "\nWarning: Some images may not have loaded correctly. Please verify and retry if necessary."
        return 1
    fi
}

upgrade_master_node() {
    echo "Upgrading control-plane node..."
    
    # Verify upgrade path
    read -p "Enter the upgrade packages path: " UPGRADE_PATH
    if [ ! -d "$UPGRADE_PATH" ]; then
        echo "Error: Directory $UPGRADE_PATH does not exist"
        return 1
    fi

    # Get list of all control-plane nodes
    CONTROL_PLANE_NODES=$(kubectl get nodes --no-headers -o custom-columns=NAME:.metadata.name,ROLES:.metadata.labels.node-role\\.kubernetes\\.io/control-plane | grep -v "<none>" | awk '{print $1}')
    
    if [ -z "$CONTROL_PLANE_NODES" ]; then
        echo "Error: No control-plane nodes found"
        return 1
    fi

    # Convert string to array
    readarray -t NODE_ARRAY <<< "$CONTROL_PLANE_NODES"
    
    # If multiple nodes found, let user select which one to upgrade
    if [ ${#NODE_ARRAY[@]} -gt 1 ]; then
        echo "Multiple control-plane nodes detected:"
        for i in "${!NODE_ARRAY[@]}"; do
            echo "[$((i+1))] ${NODE_ARRAY[$i]}"
        done
        
        while true; do
            read -p "Select which node to upgrade (1-${#NODE_ARRAY[@]}): " node_choice
            if [[ "$node_choice" =~ ^[0-9]+$ ]] && [ "$node_choice" -ge 1 ] && [ "$node_choice" -le "${#NODE_ARRAY[@]}" ]; then
                NODE_NAME="${NODE_ARRAY[$((node_choice-1))]}"
                break
            else
                echo "Invalid choice. Please select a number between 1 and ${#NODE_ARRAY[@]}"
            fi
        done
    else
        NODE_NAME="${NODE_ARRAY[0]}"
    fi

    # Verify if this is the node we're running on
    CURRENT_NODE=$(hostname)
    if [ "$NODE_NAME" != "$CURRENT_NODE" ]; then
        echo "WARNING: Selected node ($NODE_NAME) is different from current node ($CURRENT_NODE)"
        echo "Upgrade script must be run on the node being upgraded"
        read -p "Are you sure you want to continue? (y/n): " confirm
        if [[ ${confirm,,} != "y" ]]; then
            echo "Upgrade cancelled"
            return 1
        fi
    fi

    echo "Proceeding with upgrade of control-plane node: $NODE_NAME"

    # Install dependencies first
    echo "Installing dependencies..."
    sudo rpm -Uvh --force --nodeps ${UPGRADE_PATH}/kubeadm/socat-*.rpm \
        ${UPGRADE_PATH}/kubeadm/conntrack-tools-*.rpm \
        ${UPGRADE_PATH}/kubeadm/kubernetes-cni-*.rpm \
        ${UPGRADE_PATH}/kubeadm/cri-tools-*.rpm \
        ${UPGRADE_PATH}/kubeadm/ebtables-*.rpm \
        ${UPGRADE_PATH}/kubeadm/ethtool-*.rpm \
        ${UPGRADE_PATH}/kubeadm/iptables-*.rpm \
        ${UPGRADE_PATH}/kubeadm/iproute-tc-*.rpm \
        ${UPGRADE_PATH}/kubeadm/ipvsadm-*.rpm || {
        echo "Warning: Some dependencies might have failed to install"
    }

    # Install new kubeadm
    echo "Installing new kubeadm..."
    sudo rpm -Uvh --force "${UPGRADE_PATH}/kubeadm/kubeadm-${UPGRADE_KUBEADM_VERSION}"*.rpm || {
        echo "Failed to install new kubeadm"
        return 1
    }

    # Check if this is the first control-plane node
    if kubectl get nodes "$NODE_NAME" -o jsonpath='{.metadata.annotations.kubeadm\.alpha\.kubernetes\.io/init-config}' >/dev/null 2>&1; then
        echo "This appears to be the initial control-plane node. Running full upgrade..."
        # Verify upgrade plan
        sudo kubeadm upgrade plan "v${UPGRADE_K8S_VERSION}" || {
            echo "Upgrade plan verification failed"
            return 1
        }

        # Perform upgrade
        echo "Performing control plane upgrade..."
        sudo kubeadm upgrade apply "v${UPGRADE_K8S_VERSION}" --yes || {
            echo "Control plane upgrade failed"
            return 1
        }
    else
        echo "This appears to be an additional control-plane node. Running node upgrade..."
        # For additional control-plane nodes, just run upgrade node
        sudo kubeadm upgrade node || {
            echo "Node upgrade failed"
            return 1
        }
    fi

    # Drain the node
    echo "Draining control-plane node..."
    kubectl drain "$NODE_NAME" --ignore-daemonsets --delete-emptydir-data || {
        echo "Warning: Node drain had some issues, but continuing..."
    }

    # Upgrade kubelet and kubectl
    echo "Upgrading kubelet and kubectl..."
    echo "Upgrading kubelet and kubectl..."
    sudo rpm -Uvh --force --nodeps "${UPGRADE_PATH}/kubeadm/kubelet-${UPGRADE_KUBELET_VERSION}"*.rpm || {
        echo "Failed to install kubelet"
        return 1
    }
    sudo rpm -Uvh --force --nodeps "${UPGRADE_PATH}/kubeadm/kubectl-${UPGRADE_KUBECTL_VERSION}"*.rpm || {
        echo "Failed to install kubectl"
        return 1
    }

    # Restart kubelet
    sudo systemctl daemon-reload
    sudo systemctl restart kubelet

    # Uncordon the node
    echo "Uncordoning control-plane node..."
    kubectl uncordon "$NODE_NAME"

    echo "Control-plane node upgrade completed successfully!"
    
    if [ ${#NODE_ARRAY[@]} -gt 1 ]; then
        echo
        echo "IMPORTANT: Remember to upgrade other control-plane nodes:"
        for node in "${NODE_ARRAY[@]}"; do
            if [ "$node" != "$NODE_NAME" ]; then
                echo "- $node"
            fi
        done
    fi
}

upgrade_worker_node() {
    echo "Upgrading worker node..."
    
    read -p "Enter the upgrade packages path: " UPGRADE_PATH
    if [ ! -d "$UPGRADE_PATH" ]; then
        echo "Error: Directory $UPGRADE_PATH does not exist"
        return 1
    fi

    echo "Installing dependencies..."
    sudo rpm -Uvh --force --nodeps ${UPGRADE_PATH}/kubeadm/socat-*.rpm \
        ${UPGRADE_PATH}/kubeadm/conntrack-tools-*.rpm \
        ${UPGRADE_PATH}/kubeadm/kubernetes-cni-*.rpm \
        ${UPGRADE_PATH}/kubeadm/cri-tools-*.rpm \
        ${UPGRADE_PATH}/kubeadm/ebtables-*.rpm \
        ${UPGRADE_PATH}/kubeadm/ethtool-*.rpm \
        ${UPGRADE_PATH}/kubeadm/iptables-*.rpm \
        ${UPGRADE_PATH}/kubeadm/iproute-tc-*.rpm \
        ${UPGRADE_PATH}/kubeadm/ipvsadm-*.rpm || {
        echo "Warning: Some dependencies might have failed to install"
    }

    # Install new kubeadm
    echo "Installing new kubeadm..."
    sudo rpm -Uvh --force "${UPGRADE_PATH}/kubeadm/kubeadm-${UPGRADE_KUBEADM_VERSION}"*.rpm || {
        echo "Failed to install new kubeadm"
        return 1
    }

    # Upgrade node
    echo "Upgrading node configuration..."
    sudo kubeadm upgrade node || {
        echo "Node upgrade failed"
        return 1
    }

    # Upgrade kubelet
    echo "Upgrading kubelet..."
    sudo rpm -Uvh --force "${UPGRADE_PATH}/kubeadm/kubelet-${UPGRADE_KUBELET_VERSION}"*.rpm

    # Restart kubelet
    sudo systemctl daemon-reload
    sudo systemctl restart kubelet

    echo "Worker node upgrade completed successfully!"
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
            # Create directory first then copy
            ssh -i "$SSH_KEY" -o ConnectTimeout=10 ${WORKER_USER}@${WORKER_IP} "mkdir -p ~/upgrade-k8s-packages"
            if scp -i "$SSH_KEY" -o ConnectTimeout=10 -r ${UPGRADE_PACKAGES_DIR}/* ${WORKER_USER}@${WORKER_IP}:~/upgrade-k8s-packages/; then
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
            # Create directory first then copy
            SSHPASS="$WORKER_PASS" sshpass -e ssh -o StrictHostKeyChecking=no ${WORKER_USER}@${WORKER_IP} "mkdir -p ~/upgrade-k8s-packages"
            if SSHPASS="$WORKER_PASS" sshpass -e scp -o StrictHostKeyChecking=no -r ${UPGRADE_PACKAGES_DIR}/* ${WORKER_USER}@${WORKER_IP}:~/upgrade-k8s-packages/; then
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
    
    # Improved verification step
    echo -e "\nVerifying file transfer..."
    local remote_cmd="
        if [ -d ~/upgrade-k8s-packages ]; then
            echo '✓ Directory upgrade-k8s-packages exists'
            echo 'Checking transferred files:'
            if [ -d ~/upgrade-k8s-packages/kubeadm ]; then
                echo '✓ Found kubeadm directory'
                echo 'RPM packages:'
                ls -l ~/upgrade-k8s-packages/kubeadm/*.rpm 2>/dev/null || echo 'No RPM packages found'
            fi
            if [ -d ~/upgrade-k8s-packages/images ]; then
                echo '✓ Found images directory'
                ls -l ~/upgrade-k8s-packages/images/*.tar 2>/dev/null || echo 'No image tars found'
            fi
            echo -e '\nTotal size:'
            du -sh ~/upgrade-k8s-packages
        else
            echo 'Error: upgrade-k8s-packages directory not found'
            exit 1
        fi"
    
    if [ "$AUTH_METHOD" = "1" ]; then
        if ssh -i "$SSH_KEY" -o ConnectTimeout=10 ${WORKER_USER}@${WORKER_IP} "$remote_cmd"; then
            echo "Verification successful: Files transferred and verified"
        else
            echo "Warning: Verification failed or incomplete"
        fi
    else
        if SSHPASS="$WORKER_PASS" sshpass -e ssh -o StrictHostKeyChecking=no ${WORKER_USER}@${WORKER_IP} "$remote_cmd"; then
            echo "Verification successful: Files transferred and verified"
        else
            echo "Warning: Verification failed or incomplete"
        fi
    fi
}


# Main script execution
while true; do
    show_upgrade_menu
    read -p "Enter your choice: " choice

    case $choice in
        1)
            download_upgrade_packages
            ;;
        2)
            save_upgrade_images
            ;;

        3)
            transfer_files 
            ;;

        4)
            load_upgrade_images
            ;;
        5)
            upgrade_master_node
            ;;
        6)
            upgrade_worker_node
            ;;
        6)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "Invalid option"
            ;;
    esac

    read -p "Press Enter to continue..."
done
