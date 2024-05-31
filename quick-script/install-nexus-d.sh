#!/bin/bash

# Define the container name
container_name="nexus"

# Check if a container with the specified name exists
if docker ps -a --format '{{.Names}}' | grep -q "^$container_name$"; then
  # Check if the container is running
  if docker ps --format '{{.Names}}' | grep -q "^$container_name$"; then
    echo "Using existing running Nexus container: $container_name"
  else
    echo "Starting existing stopped Nexus container: $container_name"
    docker start $container_name
  fi
else
  # Start a new Nexus container with the specified name
  echo "Starting new Nexus container: $container_name"
  docker run -d --name "$container_name" -p 8081:8081 sonatype/nexus3:latest
fi

# Get the container ID
container_id=$(docker ps -qf "name=$container_name")

# Check if the container is running
if [ -z "$container_id" ]; then
  echo "Nexus container is not running."
  exit 1
fi

# Retrieve admin password
admin_password=$(docker exec $container_id cat /nexus-data/admin.password 2>/dev/null)

# Check if admin password is retrieved successfully
if [ -z "$admin_password" ]; then
  echo "Failed to retrieve admin password."
  exit 1
fi

# Store the password securely
echo "nexus_creds=$admin_password" > nexus_creds.txt

echo "Nexus admin password stored securely in nexus_creds.txt"
