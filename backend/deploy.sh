#!/bin/bash

set -e

#---------------------Utility Functions--------------------------------

install_minikube() {
    echo "Checking for minikube..."
    if command -v minikube &> /dev/null; then
        echo "minikube is already installed: $(minikube version --short)"
        return 0
    fi
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
    echo "Checking for kubectl..."
    if command -v kubectl  &> /dev/null; then
        echo "kubectl is already installed: $(kubectl version --client --short)"
        return 0
    fi

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
    echo "Checking for jq..."
    if command -v jq &> /dev/null; then
        echo "jq is already installed: $(jq --version)"
        return 0
    fi
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

#---------------------Clean Section-------------------

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

#---------------------Restart Section--------------------------------

if [ "$1" == "restart" ]; then
    echo "Restarting Docker and Minikube..."
    # Fix Docker context
    echo "Setting Docker context to default..."
    docker context use default 2>/dev/null || {
        docker context create default --docker "host=unix:///var/run/docker.sock"
        docker context use default
    }
    # Ensure Docker is running
    if ! sudo systemctl is-active --quiet docker; then
        echo "Starting Docker..."
        sudo systemctl enable docker --now
    fi
    # Restart Minikube
    echo "Restarting Minikube..."
    minikube delete || true
    rm -rf ~/.minikube
    minikube start --driver=docker --memory=4096 --cpus=2
    # Verify Minikube
    echo "Verifying Minikube..."
    minikube status
    kubectl cluster-info
    if [ "$(kubectl config current-context)" != "minikube" ]; then
        echo "Error: kubectl context is not set to minikube."
        exit 1
    fi
    exit 0
fi

#---------------------Rebuild-----------------------------

if [ "$1" == "rebuild" ]; then
    echo "Rebuilding Docker image fastapi-app:latest..."
    docker build -t fastapi-app:latest .
    if [ $? -ne 0 ]; then
        echo "Error: Docker build failed."
        exit 1
    fi

    echo "Loading image to Minikube..."
    minikube image load fastapi-app:latest
    if [ $? -ne 0 ]; then
        echo "Error: Failed to load image to Minikube."
        exit 1
    fi

    echo "Restarting fastapi-app deployment..."
    kubectl rollout restart deployment/fastapi-app
    if [ $? -ne 0 ]; then
        echo "Error: Failed to restart deployment."
        exit 1
    fi

    echo "Waiting for deployment to be ready..."
    kubectl wait --for=condition=available deployment/fastapi-app --timeout=300s
    if [ $? -ne 0 ]; then
        echo "Error: Deployment not ready within 5 minutes."
        exit 1
    fi

    echo "Rebuild and redeploy completed successfully."
    exit 0
fi

#---------------Test-------------------------- 
if [ "$1" == "test" ]; then
    echo "Running tests..."
    source venv/bin/activate
    pytest tests/test_api.py -v
    deactivate
    exit 0
fi


#----------------Port-forward section
if [ "$1" == "portforward" ]; then
    echo "Checking for redis-service..."
    kubectl get service redis-service >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: redis-service not found."
        exit 1
    fi

    echo "Checking for fastapi-service..."
    kubectl get service fastapi-service >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: fastapi-service not found."
        exit 1
    fi

    echo "Starting port-forward for redis-service (6379:6379)..."
    kubectl port-forward service/redis-service 6379:6379 &
    REDIS_PID=$!
    if ! ps -p $REDIS_PID >/dev/null; then
        echo "Error: Failed to start Redis port-forward."
        exit 1
    fi
    echo "Redis port-forward started (PID: $REDIS_PID)."

    echo "Starting port-forward for fastapi-service (8080:80)..."
    kubectl port-forward service/fastapi-service 8080:80 &
    FASTAPI_PID=$!
    if ! ps -p $FASTAPI_PID >/dev/null; then
        echo "Error: Failed to start FastAPI port-forward."
        exit 1
    fi
    echo "FastAPI port-forward started (PID: $FASTAPI_PID)."

    echo "Port-forwarding active. Press Ctrl+C to stop."
    trap 'echo "Stopping port-forwarding..."; kill $REDIS_PID $FASTAPI_PID; exit 0' INT
    wait $REDIS_PID $FASTAPI_PID
    exit 0
fi

#----------Start Redis port-forward
if [ "$1" == "redis" ]; then
    echo "Starting Redis port-forward..."
    kubectl port-forward service/redis-service 6379:6379 &
    echo "Redis port-forward started (PID: $!)."
    exit 0
fi

#----------Start FastAPI port-forward

if [ "$1" == "fastapi" ]; then
    echo "Starting FastAPI port-forward..."
    kubectl port-forward service/fastapi-service 8080:80 &
    echo "FastAPI port-forward started (PID: $!)."
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


# Testing minikube tunnel 
echo "Getting fastapi-service URL..."
# Start minikube tunnel in the background
minikube tunnel > /dev/null 2>&1 &
TUNNEL_PID=$!
sleep 5 # Wait for tunnel to establish
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
# Stop tunnel
kill $TUNNEL_PID 2>/dev/null || true

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
