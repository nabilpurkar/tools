#!/bin/bash

# Update package index
sudo apt update

# Install Nginx
sudo apt install -y nginx

# Check if Nginx is installed and running
if systemctl is-active --quiet nginx; then
    echo "Nginx installed and running successfully."
else
    echo "Nginx installation failed or could not be started. Please check the logs for errors."
fi

