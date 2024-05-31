#!/bin/bash

# Function to install AWS CLI if not already installed
install_aws_cli() {
    aws --version
    if [ $? -eq 0 ]; then
        echo -e "\e[0;31mAWS CLI is already installed.\e[0m"
    else
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        sudo apt install -y unzip
        unzip awscliv2.zip
        sudo ./aws/install
        echo -e "\e[0;31mAWS CLI is installed.\e[0m"
    fi
}

# Function to install kubectl
install_kubectl() {
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    curl -LO "https://dl.k8s.io/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    kubectl version --client
    echo -e "\e[0;31mkubectl is installed.\e[0m"
}

# Function to install eksctl
install_eksctl() {
    curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
    sudo mv /tmp/eksctl /usr/local/bin
    eksctl version
    echo -e "\e[0;31mEKSCTL is installed.\e[0m"
}

# Function to create EKS cluster
create_eks_cluster() {
    read -p "Enter EKS cluster name: " cluster_name
    read -p "Enter EKS nodegroup name: " nodegroup_name

    aws configure

    eksctl create cluster --name "$cluster_name" --version 1.26 --region us-east-1 \
        --nodegroup-name "$nodegroup_name" --node-type t3.medium --nodes 4 --managed
}

# Main script

# Install AWS CLI
install_aws_cli

# Install kubectl
install_kubectl

# Install eksctl
install_eksctl

# Create EKS cluster
create_eks_cluster

