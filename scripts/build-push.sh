#!/bin/bash
# Build and push the ModResorts image. Run from the repository root.
set -e
set -o pipefail

echo "=== ModResorts - Build & Push ==="

DEFAULT_PROJECT_NAME="modresorts"
read -r -p "Project/image name [${DEFAULT_PROJECT_NAME}]: " PROJECT_NAME
PROJECT_NAME=${PROJECT_NAME:-$DEFAULT_PROJECT_NAME}
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')
if [ -z "$IMAGE_NAME" ]; then
  echo "Invalid project name"; exit 1
fi

read -r -p "Image tag [latest]: " IMAGE_TAG
IMAGE_TAG=$(echo "${IMAGE_TAG:-latest}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._' '-' | sed 's/^-*//;s/-*$//')
IMAGE_TAG=${IMAGE_TAG:-latest}

echo "Select registry:"
echo "  1. AWS ECR"
echo "  2. Docker Hub"
read -r -p "Choice [1/2]: " REGISTRY_CHOICE

if [ "$REGISTRY_CHOICE" = "1" ]; then
  read -r -p "AWS region (e.g. us-east-1): " AWS_REGION
  read -r -p "AWS account ID: " AWS_ACCOUNT_ID
  if [ -z "$AWS_REGION" ] || [ -z "$AWS_ACCOUNT_ID" ]; then
    echo "AWS region and account ID are required"; exit 1
  fi
  ECR_REPO="$IMAGE_NAME"
  REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  FULL_IMAGE_NAME="${REGISTRY_URL}/${ECR_REPO}:${IMAGE_TAG}"

  echo "Logging in to ECR..."
  aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY_URL"

  echo "Ensuring ECR repository exists..."
  aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1 || \
    aws ecr create-repository --repository-name "$ECR_REPO" --region "$AWS_REGION"
elif [ "$REGISTRY_CHOICE" = "2" ]; then
  read -r -p "Docker Hub username: " DOCKER_USERNAME
  read -r -s -p "Docker Hub password/token: " DOCKER_PASSWORD
  echo
  if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ]; then
    echo "Docker Hub credentials are required"; exit 1
  fi
  DOCKER_USERNAME=$(echo "$DOCKER_USERNAME" | tr '[:upper:]' '[:lower:]')
  FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"

  echo "Logging in to Docker Hub..."
  echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
else
  echo "Invalid registry choice"; exit 1
fi

echo "Building image ${FULL_IMAGE_NAME}..."
docker build -f Dockerfile -t "$FULL_IMAGE_NAME" .

echo "Pushing image ${FULL_IMAGE_NAME}..."
docker push "$FULL_IMAGE_NAME"

echo "Done. Image pushed: ${FULL_IMAGE_NAME}"
echo "Use this URI with scripts/deploy-image.sh"
