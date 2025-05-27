# Multi CDN Async

### Just run the deploy.sh file

### The BASH Script Breakdown

This bash script automates the setup, management, and deployment of a FastAPI application within a Kubernetes cluster (specifically on Minikube). Here's a breakdown of what each part of the script is doing:

## Utility Functions

### `install_minikube`
- Checks if Minikube is installed.
- If not, installs Minikube based on the operating system (Linux or macOS).

### `install_kubectl`
- Checks if `kubectl` (the Kubernetes command-line tool) is installed.
- If not, installs `kubectl` for Linux or macOS.

### `install_jq`
- Checks if `jq` (a lightweight JSON processor) is installed.
- If not, installs `jq` for Linux or macOS.

### `check_dependencies`
- Ensures that Minikube, kubectl, and jq are installed. If any are missing, it installs them.

## Clean Section

### `clean`
- Stops all Docker containers and removes them, including their images.
- Stops and deletes the Minikube cluster and removes its configurations (`~/.minikube`).

## Restart Section

### `restart`
- Restarts Docker and Minikube:
  - Fixes Docker context (ensures it's using the default context).
  - Starts Docker if it's not running.
  - Deletes and restarts the Minikube cluster, allocating 4GB of memory and 2 CPUs.
- Verifies Minikube and kubectl contexts are properly set.

## Rebuild Section

### `rebuild`
- Rebuilds the Docker image (`fastapi-app:latest`).
- Loads the image into Minikube.
- Restarts the FastAPI deployment in Kubernetes.
- Waits until the deployment is available and fully ready (within 5 minutes).

## Test Section

### `test`
- Activates a Python virtual environment and runs tests using `pytest` on the `test_api.py` file.
- Deactivates the virtual environment after running tests.

## Port-Forwarding Sections

### `portforward`
- Starts port forwarding for both `redis-service` (port 6379) and `fastapi-service` (port 8080) within the Minikube cluster.
- Uses the `kubectl port-forward` command in the background for both services and prints their process IDs (PID).
- Stops port forwarding when the user interrupts (Ctrl+C).

### `redis`
- Starts port forwarding only for the `redis-service` on port 6379.

### `fastapi`
- Starts port forwarding only for the `fastapi-service` on port 8080.

## Main Script (Deployment Logic)

1. **`check_dependencies`**: Ensures Minikube, kubectl, and jq are installed.
2. **Variables**: Sets various variables including project directory, memory, CPU settings for Minikube, and file names for deployment configurations.
3. **Directory and File Checks**:
   - Verifies that the script is running in the correct project directory.
   - Checks if the required files (e.g., `Dockerfile`, `requirements.txt`, `.env`, `deployment.yaml`, `services.yaml`) are present.
4. **Docker Status**:
   - Ensures Docker is running, and starts it if necessary.
5. **Start Minikube**:
   - Starts Minikube if it's not already running and sets it up with the specified driver, memory, and CPU settings.
6. **Build Docker Image**:
   - Builds the Docker image (`fastapi-app:latest`) from the Dockerfile.
7. **Verify Image**:
   - Verifies the built Docker image is correct.
8. **Load Image into Minikube**:
   - Loads the Docker image into the Minikube environment for use within Kubernetes.
9. **Apply Kubernetes Configurations**:
   - Applies the `deployment.yaml` and `services.yaml` files using `kubectl`, which deploy the FastAPI and Redis services to the Minikube cluster.
10. **Wait for Deployments**:
    - Waits for both the FastAPI and Redis deployments to be fully available.
11. **Check Pods**:
    - Checks the status of the pods running FastAPI and Redis services.
12. **Test the FastAPI Application**:
    - Starts a Minikube tunnel to expose the `fastapi-service` externally.
    - Uses `curl` to hit the `/task/test_device` and `/task/status/{task_id}` endpoints of the FastAPI app to ensure it's working.
    - Retrieves logs from the FastAPI pod (`task.log`).
13. **Completion**:
    - Displays the URL of the `fastapi-service` and confirms the deployment is complete.

## Summary
This script is designed to automate the entire process of setting up and managing a local Kubernetes cluster (using Minikube), building and deploying a FastAPI application with Redis, and testing the service. It ensures that the environment is properly configured with necessary tools (like Docker, kubectl, Minikube, and jq), handles various deployment steps (build, load, apply, wait), and provides utilities for testing, rebuilding, restarting, and cleaning up services.

It’s ideal for developers looking to quickly set up and manage a Kubernetes-based application in a local development environment.


## Examples

### Example 1: Clean Up Environment

To stop and clean up all resources, including Docker containers, Minikube clusters, and related images, run:

```bash
./deploy.sh clean
```

### Example 2: Restart Docker and Minikube

To restart both Docker and Minikube, ensuring everything is set up correctly:
```
./deploy.sh restart
```

### Example 3: Rebuild the Docker Image and Redeploy FastAPI

To rebuild the Docker image for the FastAPI app and redeploy it to Minikube:
```
./deploy.sh rebuild
```
### Example 4: Run Tests on FastAPI

To run the tests on the FastAPI app using pytest:
```
./deploy.sh test
```
### Example 5: Start Port Forwarding for Redis and FastAPI

To start port forwarding for both the Redis and FastAPI services:
```
./deploy.sh portforward
```
### Example 6: Start Port Forwarding for Redis Only

To forward the Redis service port (6379):
```
./deploy.sh redis
```
### Example 7: Start Port Forwarding for FastAPI Only

To forward the FastAPI service port (8080):
```
./deploy.sh fastapi
```