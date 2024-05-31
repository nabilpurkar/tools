#!/bin/bash

# Function to check if Jenkins service is running
is_jenkins_running() {
    sudo systemctl is-active --quiet jenkins
}

# Function to install Java if not already installed
install_java() {
    if ! command -v java &> /dev/null; then
        # Install OpenJDK 17 if Java is not installed
        sudo apt install -y fontconfig openjdk-17-jre
    fi
}

# Check if Java is installed
install_java

# Check if Jenkins is already installed and running
if is_jenkins_running; then
    echo "Jenkins is already installed and running. Skipping installation."
    exit 0
fi

# Download Jenkins keyring if not already present
if [ ! -f /usr/share/keyrings/jenkins-keyring.asc ]; then
    sudo wget -O /usr/share/keyrings/jenkins-keyring.asc \
        https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
fi

# Add Jenkins repository to sources.list.d if not already added
if [ ! -f /etc/apt/sources.list.d/jenkins.list ]; then
    echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
    https://pkg.jenkins.io/debian-stable binary/" | sudo tee \
    /etc/apt/sources.list.d/jenkins.list > /dev/null
fi

# Update package index
sudo apt-get update

# Install Jenkins
sudo apt-get install -y jenkins

# Check if Jenkins is installed and running successfully
if is_jenkins_running; then
    echo "Jenkins installed and started successfully."
else
    echo "Jenkins installation failed or could not be started. Please check the logs for errors."
fi

# Display Java version
java -version
