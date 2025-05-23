#!/bin/bash

set -e

#---------------------Utility Functions--------------------------------

install_minikube() {
    echo "Installing minikube..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
        sudo install minikube-linux-amd64 /usr/local/bin/minikube
        rm minikube-linux-amd64
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install minikube
    else
        echo "Unsupported OS for minikube installation."
        exit 1
    fi
}

install_kubectl() {
    echo "Installing kubectl..."

    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        sudo install kubectl /usr/local/bin/kubectl
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install kubectl
    else
        echo "Unsupported OS for kubectl installation."
        exit 1
    fi
}

install_jq() {
    echo "Installing jq..."
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        sudo apt-get update && sudo apt-get install -y jq
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        brew install jq
    else
        echo "Unsupported OS for jq installation."
        exit 1
    fi
}

check_dependencies() {
    if ! command -v minikube &> /dev/null; then
        install_minikube
    fi

    if ! command -v kubectl &> /dev/null; then
        install_kubectl
    fi

    if ! command -v jq &> /dev/null; then
        install_jq
    fi
}

if [ "$1" == "clean" ]; then
  docker stop $(docker ps -aq) || true
  docker rm $(docker ps -aq) || true
  docker rmi $(docker images -q) -f || true
  docker system prune -a --volumes -f
  minikube stop
  minikube delete
  rm -rf ~/.minikube
  exit 0
fi

#---------------------Main Script--------------------------
# Script to deploy the Paramount FastAPI, Celery, and Kubernetes app
# Project directory: /home/me/projects/paramount/backend/
# Assumes: Docker, Minikube, kubectl installed; required files present

check_dependencies
# Variables
PROJECT_DIR=$(pwd)
MINIKUBE_DRIVER="docker"
MINIKUBE_MEMORY="4096"
MINIKUBE_CPUS="2"
IMAGE_NAME="fastapi-app:latest"
DEPLOYMENT_YAML="kubernetes/deployment.yaml"
SERVICES_YAML="kubernetes/services.yaml"

# Check if running in the correct directory
if [ ! -d "$PROJECT_DIR" ]; then
  echo "Error: Project directory $PROJECT_DIR does not exist."
  exit 1
fi
cd "$PROJECT_DIR"

# Verify required files
for file in Dockerfile requirements.txt main.py config.py .env "$DEPLOYMENT_YAML" "$SERVICES_YAML"; do
  if [ ! -f "$file" ]; then
    echo "Error: Required file $file is missing."
    exit 1
  fi
done

# Ensure Docker is running
echo "Checking Docker status..."
if ! sudo systemctl is-active --quiet docker; then
  echo "Starting Docker..."
  sudo systemctl enable docker --now
fi

# Start Minikube
echo "Starting Minikube..."
minikube status &>/dev/null || minikube start --driver="$MINIKUBE_DRIVER" --memory="$MINIKUBE_MEMORY" --cpus="$MINIKUBE_CPUS"

# Verify Minikube
echo "Verifying Minikube..."
minikube status
kubectl cluster-info
if [ "$(kubectl config current-context)" != "minikube" ]; then
  echo "Error: kubectl context is not set to minikube."
  exit 1
fi

# Build Docker image
echo "Building Docker image $IMAGE_NAME..."
docker build -t "$IMAGE_NAME" .

# Verify image
echo "Verifying Docker image..."
sleep 1 # Avoid race condition
docker images | grep fastapi-app || echo "Docker images output for debugging"
if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
  echo "Error: Failed to build or find $IMAGE_NAME."
  exit 1
fi
echo "Image $IMAGE_NAME found."

# Load image into Minikube
echo "Loading $IMAGE_NAME into Minikube..."
minikube image load "$IMAGE_NAME"

# Verify image in Minikube
echo "Verifying image in Minikube..."
if ! minikube image ls | grep -q "fastapi-app"; then
  echo "Error: $IMAGE_NAME not found in Minikube."
  exit 1
fi

# Apply Kubernetes deployment
echo "Applying $DEPLOYMENT_YAML..."
kubectl apply -f "$DEPLOYMENT_YAML"

# Apply Kubernetes services
echo "Applying $SERVICES_YAML..."
kubectl apply -f "$SERVICES_YAML"

# Wait for deployments to be ready
echo "Waiting for deployments to be ready..."
kubectl wait --for=condition=available deployment/fastapi-app --timeout=120s
kubectl wait --for=condition=available deployment/redis --timeout=120s

# Check pods
echo "Checking pods..."
kubectl get pods -l app=fastapi
kubectl get pods -l app=redis

# Get service URL
echo "Getting fastapi-service URL..."
SERVICE_URL=$(minikube service fastapi-service --url)
echo "Service URL: $SERVICE_URL"

# Test the app
echo "Testing /task/test_device endpoint..."
curl -s "$SERVICE_URL/task/test_device" | jq . || echo "Warning: jq not installed, install with 'sudo apt install jq'"
TASK_ID=$(curl -s "$SERVICE_URL/task/test_device" | jq -r .task_id 2>/dev/null || echo "")
if [ -n "$TASK_ID" ]; then
  echo "Testing /task/status/$TASK_ID endpoint..."
  curl -s "$SERVICE_URL/task/status/$TASK_ID" | jq . || echo "Warning: jq not installed"
else
  echo "Warning: Failed to retrieve task_id."
fi

# Check task log
echo "Checking task.log..."
POD_NAME=$(kubectl get pods -l app=fastapi -o jsonpath="{.items[0].metadata.name}")
kubectl exec "$POD_NAME" -c fastapi -- cat task.log || echo "Warning: Failed to retrieve task.log."

echo "Deployment complete! Access the app at $SERVICE_URL"

Get service URL
echo "Getting fastapi-service URL..."
SERVICE_URL=$(minikube service fastapi-service --url)
echo "Service URL: $SERVICE_URL"

# Test the app
echo "Testing /task/test_device endpoint..."
curl -s "$SERVICE_URL/task/test_device" | jq .
TASK_ID=$(curl -s "$SERVICE_URL/task/test_device" | jq -r .task_id)
if [ -n "$TASK_ID" ]; then
  echo "Testing /task/status/$TASK_ID endpoint..."
  curl -s "$SERVICE_URL/task/status/$TASK_ID" | jq .
else
  echo "Warning: Failed to retrieve task_id."
fi

# Check task log
echo "Checking task.log..."
POD_NAME=$(kubectl get pods -l app=fastapi -o jsonpath="{.items[0].metadata.name}")
kubectl exec "$POD_NAME" -c fastapi -- cat task.log || echo "Warning: Failed to retrieve task.log."

echo "Deployment complete! Access the app at $SERVICE_URL"
