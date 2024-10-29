# EKS Cluster Setup Script

## Overview
This script automates the setup of an Amazon EKS (Elastic Kubernetes Service) cluster, including the installation of required tools, configuration of AWS credentials, and creation of the cluster and node groups.

## Features
- **Prerequisite Installation**: Automatically installs AWS CLI, `kubectl`, `eksctl`, and Helm if they are not already installed.
- **AWS Credentials Check**: Verifies that the AWS CLI is configured with valid credentials.
- **OIDC Provider Setup**: Sets up an OIDC provider for your EKS cluster to enable IAM roles for service accounts.
- **Interactive Configuration**: Prompts the user for cluster details such as cluster name, node group name, region, VPC usage, subnet IDs, volume size, number of nodes, and instance type.
- **Multiple Actions**: Offers options to install prerequisites, create a cluster, create a node group, or create both the cluster and the node group in one go.

## Requirements
- **AWS CLI**: For interacting with AWS services.
- **kubectl**: For managing Kubernetes clusters.
- **eksctl**: For simplifying the creation and management of EKS clusters.
- **Helm**: For managing Kubernetes applications.

## Prerequisites
- Ensure you have a Linux environment (the script is tailored for Linux).
- You need appropriate IAM permissions to create EKS clusters and node groups.

## Usage
1. **Clone the Repository**: Clone this repository to your local machine.
2. **Make the Script Executable**: Run the following command: chmod +x eks_cluster_setup.sh

3. **Run the Script: Execute the script**: ./eks_cluster_setup.sh

4. **Follow the Prompts: The script will prompt you to input details for your EKS cluster setup.**

5. **Select an Action: Choose from the available actions**:
    1: Install prerequisites only.
    2: Create cluster only.
    3: Create node group only.
    4: Create cluster with node group (default).

**Notes**
The script uses curl to download and install the required tools.
Make sure to have unzip installed to unpack the AWS CLI installation package.
Ensure that your AWS account has permissions to create an EKS cluster and manage related resources.
License
This project is licensed under the MIT License. See the LICENSE file for details.


### Customization
Feel free to modify any sections to better suit your preferences or to add additional details about the script's functionality. Let me know if you need any further assistance!
