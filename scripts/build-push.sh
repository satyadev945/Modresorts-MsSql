#!/bin/bash
# Build and push the TestComp1 Docker image. Run from the repository root.
set -e
set -o pipefail

PROJECT_NAME="TestComp1"
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

if [ ! -f "Dockerfile" ]; then
  echo "ERROR: Dockerfile not found. Run this script from the repository root." >&2
  exit 1
fi

echo "=== Container registry ==="
echo "1. AWS ECR"
echo "2. Docker Hub"
read -r -p "Select registry [1-2]: " REGISTRY_CHOICE

read -r -p "Enter image tag [latest]: " IMAGE_TAG
IMAGE_TAG=$(echo "${IMAGE_TAG:-latest}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._' '-' | sed 's/^-*//;s/-*$//')
IMAGE_TAG=${IMAGE_TAG:-latest}

case "$REGISTRY_CHOICE" in
  1)
    read -r -p "Enter AWS region (e.g. us-east-1): " AWS_REGION
    read -r -p "Enter AWS account ID: " AWS_ACCOUNT_ID
    read -r -p "Enter ECR repository name [$IMAGE_NAME]: " ECR_REPO
    ECR_REPO=${ECR_REPO:-$IMAGE_NAME}
    if [ -z "$AWS_REGION" ] || [ -z "$AWS_ACCOUNT_ID" ]; then
      echo "ERROR: AWS region and account ID are required." >&2
      exit 1
    fi
    REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    FULL_IMAGE_NAME="${REGISTRY_URL}/${ECR_REPO}:${IMAGE_TAG}"

    echo "Logging in to Amazon ECR..."
    aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY_URL"

    echo "Ensuring ECR repository '$ECR_REPO' exists..."
    aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$AWS_REGION" >/dev/null 2>&1 || \
      aws ecr create-repository --repository-name "$ECR_REPO" --region "$AWS_REGION"
    ;;
  2)
    read -r -p "Enter Docker Hub username: " DOCKER_USERNAME
    read -r -s -p "Enter Docker Hub password or access token: " DOCKER_PASSWORD
    echo
    if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ]; then
      echo "ERROR: Docker Hub credentials are required." >&2
      exit 1
    fi
    DOCKER_REPO=$(echo "$DOCKER_USERNAME" | tr '[:upper:]' '[:lower:]')
    FULL_IMAGE_NAME="${DOCKER_REPO}/${IMAGE_NAME}:${IMAGE_TAG}"

    echo "Logging in to Docker Hub..."
    echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
    ;;
  *)
    echo "ERROR: Invalid registry selection." >&2
    exit 1
    ;;
esac

echo "Building image: $FULL_IMAGE_NAME"
docker build -f Dockerfile -t "$FULL_IMAGE_NAME" .

echo "Pushing image: $FULL_IMAGE_NAME"
docker push "$FULL_IMAGE_NAME"

echo "SUCCESS: Image pushed -> $FULL_IMAGE_NAME"
echo "Use this URI when running scripts/deploy-image.sh"
