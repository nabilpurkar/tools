# Kubernetes Installation Script

This script automates the installation of Kubernetes on Linux-based systems, allowing users to set up a Kubernetes cluster easily. It supports both master and worker node configurations and includes checks for prerequisites, OS detection, and version validation.

## Use Case

This script is intended for system administrators and developers who want to deploy a Kubernetes cluster on their local or cloud-based Linux systems. It simplifies the process of installing Kubernetes components, managing configurations, and setting up user permissions.

## Features

- Detects the underlying OS and installs appropriate packages.
- Validates Kubernetes version input.
- Configures prerequisites, including disabling swap and loading kernel modules.
- Installs `containerd`, `kubeadm`, `kubelet`, and `kubectl`.
- Initializes the master node and sets up network configurations.
- Sets up access permissions for non-root users.
- Supports the addition of worker nodes to the cluster.

## Prerequisites

- The script must be run with root privileges.
- A supported Linux distribution (Ubuntu, Debian, CentOS, Red Hat).
- Basic networking configurations should be in place.

