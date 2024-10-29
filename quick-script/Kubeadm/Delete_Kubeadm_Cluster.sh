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

# Stop services
stop_services() {
    log "Stopping Kubernetes services..."
    systemctl stop kubelet || error "Failed to stop kubelet"
    systemctl stop containerd || error "Failed to stop containerd"
}

# Uninstall Kubernetes packages
uninstall_kubernetes() {
    log "Uninstalling Kubernetes packages..."
    sudo apt-mark unhold kubelet kubeadm kubectl
    sudo apt-get purge -y kubelet kubeadm kubectl containerd.io || error "Failed to remove Kubernetes packages"

    log "Removing Kubernetes configuration files..."
    sudo rm -rf /etc/kubernetes $HOME/.kube

    log "Cleaning up..."
    sudo apt-get autoremove -y
    sudo apt-get clean
}

# Clean up remaining directories and files
cleanup() {
    log "Cleaning up remaining directories..."
    sudo rm -rf /etc/cni/net.d /var/lib/kubelet /var/lib/etcd /var/run/kubernetes
}

# Kill remaining Kubernetes processes
kill_processes() {
    log "Killing remaining Kubernetes processes..."
    pkill -9 kube-apiserver kube-controller-manager kube-scheduler etcd || true
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
    stop_services
    uninstall_kubernetes
    kill_processes
    cleanup
    cleanup_network
    restart_containerd

    log "Kubernetes and its components have been processed. Please check above for any errors."
}

# Start the uninstallation
main
