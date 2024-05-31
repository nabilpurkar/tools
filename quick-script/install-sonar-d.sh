#!/bin/bash

# Define the container name
container_name="sonar"

# Check if a container with the specified name exists
if docker ps -a --format '{{.Names}}' | grep -q "^$container_name$"; then
  # Check if the container is running
  if docker ps --format '{{.Names}}' | grep -q "^$container_name$"; then
    echo "Using existing running SonarQube container: $container_name"
  else
    echo "Starting existing stopped SonarQube container: $container_name"
    docker start $container_name
  fi
else
  # Start a new SonarQube container with the specified name
  echo "Starting new SonarQube container: $container_name"
  docker run -d --name "$container_name" -p 9000:9000 sonarqube:lts-community
fi

# Get the container ID
container_id=$(docker ps -qf "name=$container_name")

# Check if the container is running
if [ -z "$container_id" ]; then
  echo "SonarQube container is not running."
  exit 1
fi

# Output the access URL
echo "SonarQube server is running. Access it by opening a web browser and navigating to http://localhost:9000."
