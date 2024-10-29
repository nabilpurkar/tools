# EKS Cluster Setup and EBS CSI Driver Installation Scripts

## Overview
This repository contains scripts for automating the setup of an Amazon EKS (Elastic Kubernetes Service) cluster and the installation of the Amazon EBS CSI driver. The scripts help streamline the process of configuring your EKS environment and managing storage.

## Features
### EKS Cluster Setup Script
- **Prerequisite Installation**: Automatically installs AWS CLI, `kubectl`, `eksctl`, and Helm if they are not already installed.
- **AWS Credentials Check**: Verifies that the AWS CLI is configured with valid credentials.
- **OIDC Provider Setup**: Sets up an OIDC provider for your EKS cluster to enable IAM roles for service accounts.
- **Interactive Configuration**: Prompts the user for cluster details such as cluster name, node group name, region, VPC usage, subnet IDs, volume size, number of nodes, and instance type.
- **Multiple Actions**: Offers options to install prerequisites, create a cluster, create a node group, or create both the cluster and the node group in one go.

### EBS CSI Driver Setup Script
- **Fetch Available Clusters**: Retrieves and displays available EKS clusters.
- **OIDC URL Extraction**: Extracts the OIDC URL from the selected cluster.
- **Trust Policy Creation**: Generates a trust policy file for the EBS CSI driver.
- **Role Management**: Checks if the specified IAM role exists, deletes it if necessary, and creates a new one with the trust policy.
- **Policy Attachment**: Attaches the necessary policy to the IAM role.
- **Addon Creation**: Creates the EBS CSI Driver addon in the selected EKS cluster.

## Requirements
- **AWS CLI**: For interacting with AWS services.
- **kubectl**: For managing Kubernetes clusters.
- **eksctl**: For simplifying the creation and management of EKS clusters.
- **Helm**: For managing Kubernetes applications.

## Prerequisites
- Ensure you have a Linux environment (the scripts are tailored for Linux).
- You need appropriate IAM permissions to create EKS clusters and manage related resources.

## Usage
### EKS Cluster Setup Script
1. **Clone the Repository**: Clone this repository to your local machine.
2. **Make the Script Executable**: Run the following command: chmod +x eks_cluster_setup.sh

3. **Run the Script: Execute the script**: ./eks_cluster_setup.sh

4. **Follow the Prompts**: The script will prompt you to input details for your EKS cluster setup.

5. **Select an Action: Choose from the available actions**:
        1: Install prerequisites only.
        2: Create cluster only.
        3: Create node group only.
        4: Create cluster with node group (default).

### EBS CSI Driver Setup Script
1. **Make the Script Executable**: Run the following command: chmod +x ebs_csi_driver_setup.sh
2. **Run the Script: Execute the script**: ./ebs_csi_driver_setup.sh

3. **Follow the Prompts**: The script will fetch available EKS clusters and allow you to set up the EBS CSI Driver for the selected cluster.

### Notes
The scripts use curl to download and install the required tools (in the EKS setup script).
Ensure that your AWS account has permissions to create an EKS cluster and manage related resources.
The EBS CSI Driver setup script assumes that the EKS cluster is already created.
License
This project is licensed under the MIT License. See the LICENSE file for details.


### Summary
This version clearly outlines the steps for running each script and includes the additional details you requested for ease of understanding. Let me know if you need any more changes or further assistance!
