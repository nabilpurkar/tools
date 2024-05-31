#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Function to display messages
echo_msg() {
    echo -e "\e[1;32m$1\e[0m"
}

# Update package index
echo_msg "Updating package index..."
sudo apt update

# Install required packages
echo_msg "Installing required packages for Docker..."
sudo apt install -y apt-transport-https ca-certificates curl software-properties-common

# Add Docker’s official GPG key
echo_msg "Adding Docker’s official GPG key..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -

# Verify Docker's GPG key (optional)
echo_msg "Verifying Docker's GPG key..."
sudo apt-key fingerprint 0EBFCD88

# Add the Docker repository to APT sources
echo_msg "Setting up the Docker repository..."
sudo add-apt-repository \
    "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

# Update the package index with Docker packages
echo_msg "Updating package index with Docker packages..."
sudo apt update

# Install Docker
echo_msg "Installing Docker..."
sudo apt install -y docker-ce

# Verify Docker installation
echo_msg "Verifying Docker installation..."
docker --version

# Add user to the docker group (optional)
if [ "$1" == "--non-root" ]; then
    echo_msg "Adding user to the docker group..."
    sudo usermod -aG docker ${USER}
    echo_msg "You need to log out and back in to apply the new group membership."
fi
sudo chmod 666 /var/run/docker.sock
echo_msg "Docker installation completed successfully."
