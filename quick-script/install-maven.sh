#!/bin/bash

# Function to install Maven
install_maven() {
    echo "Installing Maven..."
    wget https://dlcdn.apache.org/maven/maven-3/3.9.7/binaries/apache-maven-3.9.7-bin.tar.gz
    tar xzvf apache-maven-3.9.7-bin.tar.gz
    sudo mv apache-maven-3.9.7 /opt/apache-maven-3.9.7
    export MAVEN_HOME=/opt/apache-maven-3.9.7
    export PATH=$MAVEN_HOME/bin:$PATH
    echo "Maven installed successfully!"
    mvn -v
}

# Function to remove Maven
remove_maven() {
    echo "Removing Maven..."
    sudo rm -rf /opt/apache-maven-3.9.7
    export PATH=$(echo $PATH | sed -e 's;:/opt/apache-maven-3.9.7/bin;;')
    echo "Maven removed successfully!"
}

# Ask user whether to install or remove Maven
echo "Do you want to install or remove Maven? (install/remove)"
read action

if [ "$action" == "install" ]; then
    install_maven
elif [ "$action" == "remove" ]; then
    remove_maven
else
    echo "Invalid action. Please enter 'install' or 'remove'."
fi
