#!/bin/bash

# Function to get EKS cluster name
get_cluster_name() {
    cluster_name=$(aws eks list-clusters --output json | jq -r '.clusters[0]')
    echo "$cluster_name"
}

# Function to delete EKS cluster
delete_cluster() {
    eksctl delete cluster "$1"
}

# Main script

# Fetching cluster name
cluster_name=$(get_cluster_name)

if [ -z "$cluster_name" ]; then
    echo "No EKS cluster found."
    exit 1
fi

echo "EKS Cluster found: $cluster_name"

# Deleting cluster
delete_cluster "$cluster_name"

