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

# Function to get initial action choice
get_initial_action() {
    print_message "$GREEN" "Welcome To AWS EKS Setup How Do You Want To Setup?"
    read -p "
1. Install prerequisites only
2. Create cluster only 
3. Create nodegroup only
4. Create cluster with nodegroup (default)
5. Delete cluster
6. Delete nodegroup
Enter 1, 2, 3, 4, 5, or 6: " ACTION
    ACTION=${ACTION:-4}
}

# Function to list available clusters
list_clusters() {
    print_message "$YELLOW" "Fetching available EKS clusters..."
    local clusters=$(aws eks list-clusters --output json | jq -r '.clusters[]')
    if [ -z "$clusters" ]; then
        print_message "$RED" "No EKS clusters found in the current region."
        return 1
    fi
    print_message "$GREEN" "Available clusters:"
    echo "$clusters"
    return 0
}

# Function to list nodegroups in a cluster
list_nodegroups() {
    local cluster_name="$1"
    print_message "$YELLOW" "Fetching nodegroups for cluster: $cluster_name"
    local nodegroups=$(aws eks list-nodegroups --cluster-name "$cluster_name" --output json | jq -r '.nodegroups[]')
    if [ -z "$nodegroups" ]; then
        print_message "$RED" "No nodegroups found in cluster: $cluster_name"
        return 1
    fi
    print_message "$GREEN" "Available nodegroups:"
    echo "$nodegroups"
    return 0
}

# Function to delete nodegroup
delete_nodegroup() {
    # First, list available clusters
    if ! list_clusters; then
        return 1
    fi
    
    # Get cluster name
    read -p "Enter the name of the cluster containing the nodegroup: " cluster_name
    if [ -z "$cluster_name" ]; then
        print_message "$RED" "No cluster name provided."
        return 1
    fi

    # List nodegroups in the selected cluster
    if ! list_nodegroups "$cluster_name"; then
        return 1
    fi

    # Get nodegroup name
    read -p "Enter the name of the nodegroup to delete: " nodegroup_name
    if [ -z "$nodegroup_name" ]; then
        print_message "$RED" "No nodegroup name provided."
        return 1
    fi

    # Confirm deletion
    read -p "Are you sure you want to delete nodegroup '$nodegroup_name' from cluster '$cluster_name'? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        print_message "$YELLOW" "Nodegroup deletion cancelled."
        return 0
    fi

    print_message "$YELLOW" "Deleting nodegroup: $nodegroup_name from cluster: $cluster_name"
    if ! eksctl delete nodegroup --cluster="$cluster_name" --name="$nodegroup_name" --wait; then
        print_message "$RED" "Failed to delete nodegroup: $nodegroup_name"
        return 1
    fi
    print_message "$GREEN" "Successfully deleted nodegroup: $nodegroup_name"
}

# Function to delete cluster
delete_cluster() {
    local cluster_to_delete
    
    if [ -n "$1" ]; then
        cluster_to_delete="$1"
    else
        if ! list_clusters; then
            return 1
        fi
        
        read -p "Enter the name of the cluster to delete: " cluster_to_delete
    fi
    
    if [ -z "$cluster_to_delete" ]; then
        print_message "$RED" "No cluster name provided."
        return 1
    fi

    # Confirm deletion
    read -p "Are you sure you want to delete cluster '$cluster_to_delete'? (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        print_message "$YELLOW" "Cluster deletion cancelled."
        return 0
    fi

    print_message "$YELLOW" "Deleting EKS cluster: $cluster_to_delete"
    if ! eksctl delete cluster --name="$cluster_to_delete" --wait; then
        print_message "$RED" "Failed to delete cluster: $cluster_to_delete"
        return 1
    fi
    print_message "$GREEN" "Successfully deleted cluster: $cluster_to_delete"
}

# Main menu for cluster configuration
configure_cluster() {
    if [ "$ACTION" != "1" ] && [ "$ACTION" != "5" ] && [ "$ACTION" != "6" ]; then
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
    fi
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
    # Get initial action choice first
    get_initial_action

    # Check AWS credentials
    check_credentials

    case $ACTION in
        1)
            install_prerequisites
            print_message "$GREEN" "Prerequisites installed successfully. No further actions taken."
            ;;
        2)
            configure_cluster
            install_prerequisites
            create_cluster
            ;;
        3)
            configure_cluster
            install_prerequisites
            create_nodegroup
            ;;
        4)
            configure_cluster
            install_prerequisites
            create_cluster
            setup_oidc_provider
            create_nodegroup
            ;;
        5)
            install_prerequisites
            delete_cluster
            ;;
        6)
            install_prerequisites
            delete_nodegroup
            ;;
        *)
            print_message "$RED" "Invalid action selected. Exiting."
            exit 1
            ;;
    esac

    if [[ "$ACTION" != "5" && "$ACTION" != "6" ]]; then
        print_message "$GREEN" "EKS cluster setup completed successfully!"
        print_message "$YELLOW" "You can now use 'kubectl' to interact with your cluster"
    fi
}

# Run main function
main
