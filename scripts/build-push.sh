#!/bin/bash
set -e

# Run from the repository root (docker build context is ".")
PROJECT_NAME="TestComp1"
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

sanitize_tag() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-' | sed 's/^[-.]*//;s/[-.]*$//'
}

echo "=== Build and push ${PROJECT_NAME} ==="
echo "Select registry:"
echo "  1. AWS ECR"
echo "  2. Docker Hub"
read -r -p "Enter choice [1-2]: " REGISTRY_CHOICE

read -r -p "Enter image tag [latest]: " IMAGE_TAG
IMAGE_TAG=$(sanitize_tag "${IMAGE_TAG:-latest}")
if [ -z "$IMAGE_TAG" ]; then
  IMAGE_TAG="latest"
fi

case "$REGISTRY_CHOICE" in
  1)
    read -r -p "Enter AWS region (e.g. us-east-1): " AWS_REGION
    read -r -p "Enter AWS account ID: " AWS_ACCOUNT_ID
    if [ -z "$AWS_REGION" ] || [ -z "$AWS_ACCOUNT_ID" ]; then
      echo "AWS region and account ID are required."
      exit 1
    fi
    read -r -p "Enter ECR repository name [${IMAGE_NAME}]: " ECR_REPO
    ECR_REPO=${ECR_REPO:-$IMAGE_NAME}
    REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    FULL_IMAGE_NAME="${REGISTRY_URL}/${ECR_REPO}:${IMAGE_TAG}"

    echo "Logging in to ECR..."
    aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY_URL"

    echo "Checking ECR repository..."
    aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1 || \
      aws ecr create-repository --repository-name "$ECR_REPO" --region "$AWS_REGION"
    ;;
  2)
    read -r -p "Enter Docker Hub username: " DOCKER_USERNAME
    read -r -s -p "Enter Docker Hub password or access token: " DOCKER_PASSWORD
    echo
    if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ]; then
      echo "Docker Hub credentials are required."
      exit 1
    fi
    read -r -p "Enter repository name [${IMAGE_NAME}]: " DOCKER_REPO
    DOCKER_REPO=${DOCKER_REPO:-$IMAGE_NAME}
    DOCKER_USER_LC=$(echo "$DOCKER_USERNAME" | tr '[:upper:]' '[:lower:]')
    FULL_IMAGE_NAME="${DOCKER_USER_LC}/${DOCKER_REPO}:${IMAGE_TAG}"

    echo "Logging in to Docker Hub..."
    echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
    ;;
  *)
    echo "Invalid choice."
    exit 1
    ;;
esac

echo "Building image: ${FULL_IMAGE_NAME}"
docker build -f Dockerfile -t "$FULL_IMAGE_NAME" .

echo "Pushing image: ${FULL_IMAGE_NAME}"
docker push "$FULL_IMAGE_NAME"

echo "Done. Image pushed: ${FULL_IMAGE_NAME}"
echo "Use this URI when running scripts/deploy-image.sh"
