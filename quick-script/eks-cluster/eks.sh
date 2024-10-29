#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install prerequisites
install_prerequisites() {
    print_message "$YELLOW" "Checking and installing prerequisites..."

    # Install AWS CLI if not present
    if ! command_exists aws; then
        print_message "$YELLOW" "Installing AWS CLI..."
        curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
        unzip awscliv2.zip
        sudo ./aws/install
        rm -rf aws awscliv2.zip
    fi

    # Install kubectl if not present
    if ! command_exists kubectl; then
        print_message "$YELLOW" "Installing kubectl..."
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl
        sudo mv kubectl /usr/local/bin/
    fi

    # Install eksctl if not present
    if ! command_exists eksctl; then
        print_message "$YELLOW" "Installing eksctl..."
        ARCH=amd64
        PLATFORM=$(uname -s)_$ARCH
        curl -sLO "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
        tar -xzf eksctl_$PLATFORM.tar.gz
        sudo mv eksctl /usr/local/bin/
        rm eksctl_$PLATFORM.tar.gz
    fi

    # Install Helm if not present
    if ! command_exists helm; then
        print_message "$YELLOW" "Installing Helm..."
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi

    print_message "$GREEN" "All prerequisites installed successfully!"
}

# Function to check AWS credentials
check_credentials() {
    if ! aws sts get-caller-identity &>/dev/null; then
        print_message "$RED" "AWS credentials not configured or invalid."
        print_message "$YELLOW" "Please run 'aws configure' to set up your credentials."
        exit 1
    fi
}

# Function to set up OIDC provider
setup_oidc_provider() {
    print_message "$YELLOW" "Setting up OIDC provider..."
    if ! eksctl utils associate-iam-oidc-provider --region "$REGION" --cluster "$CLUSTER_NAME" --approve; then
        print_message "$RED" "Failed to set up OIDC provider"
        exit 1
    fi
    print_message "$GREEN" "OIDC provider setup completed"
}

# Main menu for cluster configuration
configure_cluster() {
    print_message "$YELLOW" "Please enter the following details for your EKS cluster setup:"

    read -p "Cluster Name [default: eks]: " CLUSTER_NAME
    CLUSTER_NAME=${CLUSTER_NAME:-"eks"}

    read -p "Nodegroup Name [default: eks-ng]: " NODEGROUP_NAME
    NODEGROUP_NAME=${NODEGROUP_NAME:-"eks-ng"}

    read -p "Region [default: us-east-1]: " REGION
    REGION=${REGION:-"us-east-1"}

    read -p "Do you want to use an existing VPC? (y/n): " USE_EXISTING_VPC
    if [[ "$USE_EXISTING_VPC" == "y" ]]; then
        read -p "Enter VPC ID: " VPC_ID
        read -p "Enter comma-separated subnet IDs (public and/or private): " SUBNET_IDS
        SUBNET_CONFIG="--vpc-private-subnets=$SUBNET_IDS --vpc-public-subnets=$SUBNET_IDS"
    else
        read -p "Enter comma-separated public subnet IDs: " PUBLIC_SUBNETS
        SUBNET_CONFIG="--vpc-public-subnets=$PUBLIC_SUBNETS"
    fi

    read -p "Node Volume Size (GB) [default: 15]: " NODE_VOLUME_SIZE
    NODE_VOLUME_SIZE=${NODE_VOLUME_SIZE:-15}

    read -p "Number of Nodes [default: 2]: " NODES
    NODES=${NODES:-2}

    read -p "Node Instance Type [default: t3.medium]: " NODE_INSTANCE_TYPE
    NODE_INSTANCE_TYPE=${NODE_INSTANCE_TYPE:-"t3.medium"}

    read -p "What do you want to do? 
1. Install prerequisites only
2. Create cluster only 
3. Create nodegroup only
4. Create cluster with nodegroup (default)
Enter 1, 2, 3, or 4: " ACTION
    ACTION=${ACTION:-4}
}

# Function to create the cluster
create_cluster() {
    print_message "$YELLOW" "Creating EKS Cluster $CLUSTER_NAME..."

    local create_cmd="eksctl create cluster \
        --name=$CLUSTER_NAME \
        --region=$REGION \
        --version=$VERSION \
        $SUBNET_CONFIG \
        --without-nodegroup"

    if ! $create_cmd; then
        if ! eksctl get cluster --name="$CLUSTER_NAME" --region="$REGION" &>/dev/null; then
            print_message "$RED" "Failed to create EKS Cluster $CLUSTER_NAME"
            exit 1
        else
            print_message "$GREEN" "EKS Cluster $CLUSTER_NAME already exists. Proceeding with the next steps."
        fi
    else
        print_message "$GREEN" "EKS Cluster $CLUSTER_NAME created successfully"
    fi
}

# Function to create nodegroup
create_nodegroup() {
    print_message "$YELLOW" "Creating nodegroup..."

    local nodegroup_cmd="eksctl create nodegroup \
        --cluster=$CLUSTER_NAME \
        --region=$REGION \
        --name=$NODEGROUP_NAME \
        --nodes=$NODES \
        --nodes-min=1 \
        --nodes-max=4 \
        --managed \
        --node-type=$NODE_INSTANCE_TYPE \
        --node-volume-size=$NODE_VOLUME_SIZE \
        --asg-access \
        --external-dns-access \
        --full-ecr-access \
        --appmesh-access \
        --alb-ingress-access"

    if [ "$USE_EXISTING_VPC" == "y" ] && [ -n "$VPC_ID" ]; then
        nodegroup_cmd="$nodegroup_cmd --node-private-networking"
    fi

    if ! $nodegroup_cmd; then
        if ! eksctl get nodegroup --cluster="$CLUSTER_NAME" --region="$REGION" --name="$NODEGROUP_NAME" &>/dev/null; then
            print_message "$RED" "Failed to create nodegroup"
            exit 1
        else
            print_message "$GREEN" "Nodegroup already exists. Proceeding with the next steps."
        fi
    else
        print_message "$GREEN" "Nodegroup created successfully"
    fi
}

# Main execution
main() {
    print_message "$GREEN" "EKS Cluster Setup Script"
    print_message "$YELLOW" "Checking prerequisites..."

    # Install prerequisites
    install_prerequisites

    # Check AWS credentials
    check_credentials

    # Configure cluster
    configure_cluster

    case $ACTION in
        1)
            print_message "$GREEN" "Prerequisites installed successfully. No further actions taken."
            ;;
        2)
            create_cluster
            ;;
        3)
            create_nodegroup
            ;;
        4)
            create_cluster
            setup_oidc_provider
            create_nodegroup
            ;;
        *)
            print_message "$RED" "Invalid action selected. Exiting."
            exit 1
            ;;
    esac

    print_message "$GREEN" "EKS cluster setup completed successfully!"
    print_message "$YELLOW" "You can now use 'kubectl' to interact with your cluster"
}

# Run main function
main
