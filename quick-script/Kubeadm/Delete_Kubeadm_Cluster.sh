#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Log function
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

# Error function
error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect OS type
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        OS=$(uname -s)
    fi
    log "Detected OS: $OS"
}

# Stop services
stop_services() {
    log "Stopping Kubernetes services..."
    systemctl stop kubelet || error "Failed to stop kubelet"
    systemctl stop containerd || error "Failed to stop containerd"
}

# Uninstall Kubernetes packages
uninstall_kubernetes() {
    log "Uninstalling Kubernetes packages..."

    if [ "$OS" == "ubuntu" ]; then
        sudo apt-mark unhold kubelet kubeadm kubectl
        sudo apt-get purge -y kubelet kubeadm kubectl containerd.io || error "Failed to remove Kubernetes packages"
        sudo apt-get autoremove -y
        sudo apt-get clean
    elif [ "$OS" == "rhel" ] || [ "$OS" == "centos" ]; then
        sudo yum remove -y kubelet kubeadm kubectl containerd.io || error "Failed to remove Kubernetes packages"
        sudo yum autoremove -y
    else
        error "Unsupported OS: $OS"
        exit 1
    fi

    log "Removing Kubernetes configuration files..."
    sudo rm -rf /etc/kubernetes $HOME/.kube
}

# Clean up remaining directories and files
cleanup() {
    log "Cleaning up remaining directories..."
    sudo rm -rf /etc/cni/net.d /var/lib/kubelet /var/lib/etcd /var/run/kubernetes
}

# Kill remaining Kubernetes processes
kill_processes() {
    log "Killing remaining Kubernetes processes..."
    sudo pkill -9 kube-apiserver || true
    sudo pkill -9 kube-controller-manager || true
    sudo pkill -9 kube-scheduler || true
    sudo pkill -9 etcd || true
}

# Clean up network rules
cleanup_network() {
    log "Cleaning up network rules..."
    sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X
    sudo ipvsadm -C || true
}

# Restart containerd
restart_containerd() {
    log "Restarting containerd..."
    sudo systemctl restart containerd || error "Failed to restart containerd"
}

# Main function
main() {
    detect_os
    stop_services
    uninstall_kubernetes
    kill_processes
    cleanup
    cleanup_network
    restart_containerd

    log "Kubernetes and its components have been processed. Please check above for any errors."
    sudo netstat -tuln | grep -E '6443|10257|10259|2379|2380' || log "No remaining Kubernetes ports open."
    sudo lsof -iTCP -sTCP:LISTEN -P | grep -E ':(6443|10257|10259|2379|2380)'
    sudo ss -tuln | grep -E ':(6443|10257|10259|2379|2380)'
}

# Start the uninstallation
main
