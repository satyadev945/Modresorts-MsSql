#!/bin/bash
# Build and push the ModResorts Docker image. Run from the repository root.
set -e
set -o pipefail

PROJECT_NAME="modresorts"
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

echo "=== ModResorts Docker build and push ==="
read -r -p "Enter image tag [latest]: " IMAGE_TAG
IMAGE_TAG=$(echo "$IMAGE_TAG" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._' '-' | sed 's/^-*//;s/-*$//')
IMAGE_TAG=${IMAGE_TAG:-latest}

echo "Select registry:"
echo "  1. AWS ECR"
echo "  2. Docker Hub"
read -r -p "Choice [1/2]: " REGISTRY_CHOICE

if [ "$REGISTRY_CHOICE" = "1" ]; then
  read -r -p "Enter AWS region (e.g. us-east-1): " AWS_REGION
  read -r -p "Enter AWS account ID: " AWS_ACCOUNT_ID
  read -r -p "Enter ECR repository name [$IMAGE_NAME]: " ECR_REPO
  ECR_REPO=${ECR_REPO:-$IMAGE_NAME}
  if [ -z "$AWS_REGION" ] || [ -z "$AWS_ACCOUNT_ID" ]; then
    echo "AWS region and account ID are required"; exit 1
  fi
  REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  FULL_IMAGE_NAME="${REGISTRY_URL}/${ECR_REPO}:${IMAGE_TAG}"

  echo "Logging in to ECR..."
  aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY_URL"

  echo "Ensuring ECR repository exists..."
  aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1 || aws ecr create-repository --repository-name "$ECR_REPO" --region "$AWS_REGION"
elif [ "$REGISTRY_CHOICE" = "2" ]; then
  read -r -p "Enter Docker Hub username: " DOCKER_USERNAME
  read -r -s -p "Enter Docker Hub password/token: " DOCKER_PASSWORD
  echo
  read -r -p "Enter repository name [$IMAGE_NAME]: " DOCKER_REPO
  DOCKER_REPO=${DOCKER_REPO:-$IMAGE_NAME}
  if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ]; then
    echo "Docker Hub credentials are required"; exit 1
  fi
  FULL_IMAGE_NAME="${DOCKER_USERNAME}/${DOCKER_REPO}:${IMAGE_TAG}"

  echo "Logging in to Docker Hub..."
  echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
else
  echo "Invalid registry choice"; exit 1
fi

echo "Building image $FULL_IMAGE_NAME ..."
docker build -f Dockerfile -t "$FULL_IMAGE_NAME" .

echo "Pushing image $FULL_IMAGE_NAME ..."
docker push "$FULL_IMAGE_NAME"

echo "Done. Image pushed: $FULL_IMAGE_NAME"
echo "Use this URI with scripts/deploy-image.sh"
