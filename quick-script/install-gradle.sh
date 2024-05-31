#!/bin/bash

# Function to install Gradle
install_gradle() {
    echo "Installing Gradle..."
    wget https://services.gradle.org/distributions/gradle-8.7-all.zip -O gradle-8.7-all.zip
    sudo mkdir -p /opt/gradle
    sudo unzip -d /opt/gradle gradle-8.7-all.zip
    GRADLE_DIR=/opt/gradle/gradle-8.7
    export PATH=$PATH:$GRADLE_DIR/bin
    echo "Gradle installed successfully!"
    gradle -v
}

# Function to remove Gradle
remove_gradle() {
    echo "Removing Gradle..."
    sudo rm -rf /opt/gradle/gradle-8.7
    export PATH=$(echo $PATH | sed -e 's;:/opt/gradle/gradle-8.7/bin;;')
    echo "Gradle removed successfully!"
}

# Ask user whether to install or remove Gradle
echo "Do you want to install or remove Gradle? (install/remove)"
read action

if [ "$action" == "install" ]; then
    install_gradle
elif [ "$action" == "remove" ]; then
    remove_gradle
else
    echo "Invalid action. Please enter 'install' or 'remove'."
fi

