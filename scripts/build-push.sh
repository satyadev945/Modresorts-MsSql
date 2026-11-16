#!/bin/bash
set -e
set -o pipefail

# Run from repository root: ./scripts/build-push.sh
PROJECT_NAME="modresorts"

sanitize() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-' | sed 's/^-*//;s/-*$//'
}

IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

read -r -p "Enter image tag [latest]: " IMAGE_TAG
IMAGE_TAG=$(sanitize "${IMAGE_TAG:-latest}")
IMAGE_TAG=${IMAGE_TAG:-latest}

echo "Select registry type:"
echo "  1. Azure Container Registry (ACR)"
echo "  2. Docker Hub"
read -r -p "Enter choice [1-2]: " REGISTRY_CHOICE

case "$REGISTRY_CHOICE" in
  1)
    read -r -p "Enter ACR name (without .azurecr.io): " ACR_NAME
    if [ -z "$ACR_NAME" ]; then echo "ACR name is required"; exit 1; fi
    ACR_NAME=$(echo "$ACR_NAME" | tr '[:upper:]' '[:lower:]')
    echo "Logging in to ACR $ACR_NAME ..."
    az acr login --name "$ACR_NAME"
    FULL_IMAGE_NAME="${ACR_NAME}.azurecr.io/${IMAGE_NAME}:${IMAGE_TAG}"
    ;;
  2)
    read -r -p "Enter Docker Hub username: " DOCKER_USERNAME
    read -r -s -p "Enter Docker Hub password or access token: " DOCKER_PASSWORD
    echo ""
    if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ]; then echo "Credentials are required"; exit 1; fi
    DOCKER_USERNAME=$(echo "$DOCKER_USERNAME" | tr '[:upper:]' '[:lower:]')
    echo "Logging in to Docker Hub ..."
    echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
    FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"
    ;;
  *)
    echo "Invalid choice"; exit 1
    ;;
esac

echo "Building image $FULL_IMAGE_NAME ..."
docker build -f Dockerfile -t "$FULL_IMAGE_NAME" .

echo "Pushing image $FULL_IMAGE_NAME ..."
docker push "$FULL_IMAGE_NAME"

echo ""
echo "Done. Image pushed: $FULL_IMAGE_NAME"
echo "Deploy with: ./scripts/deploy-image.sh (use the image URI above)"
