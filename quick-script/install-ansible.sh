#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Set the Ubuntu codename
UBUNTU_CODENAME=focal

# Define the key URL and the keyring path
KEY_URL="https://keyserver.ubuntu.com/pks/lookup?fingerprint=on&op=get&search=0x6125E2A8C77F2818FB7BD15B93C4A3FD7BB9C367"
KEYRING_PATH="/usr/share/keyrings/ansible-archive-keyring.gpg"

# Download and save the GPG key
wget -qO- "$KEY_URL" | sudo gpg --dearmor -o "$KEYRING_PATH"

# Add the Ansible PPA to the sources list
echo "deb [signed-by=$KEYRING_PATH] http://ppa.launchpad.net/ansible/ansible/ubuntu $UBUNTU_CODENAME main" | sudo tee /etc/apt/sources.list.d/ansible.list > /dev/null

# Update package lists
sudo apt update

# Install Ansible core dependencies
sudo apt install -y ansible-core

# Install Ansible
sudo apt install -y ansible

# Print success message
echo "Ansible has been successfully installed."
