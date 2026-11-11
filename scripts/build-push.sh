#!/bin/bash
# Build and push the ModResorts image. Run from the repository root.
set -e
set -o pipefail

PROJECT_NAME="modresorts"
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')

echo "=== ModResorts image build & push ==="
echo "Select registry:"
echo "  1. Google Artifact Registry"
echo "  2. Docker Hub"
read -r -p "Choice [1/2]: " REGISTRY_CHOICE

read -r -p "Image tag [latest]: " IMAGE_TAG
IMAGE_TAG=$(echo "$IMAGE_TAG" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._' '-' | sed 's/^-*//;s/-*$//')
IMAGE_TAG=${IMAGE_TAG:-latest}

case "$REGISTRY_CHOICE" in
  1)
    read -r -p "GCP project ID: " GCP_PROJECT
    read -r -p "Artifact Registry region (e.g. us-central1): " GCP_REGION
    read -r -p "Artifact Registry repository name: " AR_REPO
    if [ -z "$GCP_PROJECT" ] || [ -z "$GCP_REGION" ] || [ -z "$AR_REPO" ]; then
      echo "ERROR: project, region and repository are required"; exit 1
    fi
    FULL_IMAGE_NAME="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT}/${AR_REPO}/${IMAGE_NAME}:${IMAGE_TAG}"
    echo "Authenticating with Google Cloud..."
    gcloud auth login --brief || true
    gcloud config set project "$GCP_PROJECT"
    gcloud auth configure-docker "${GCP_REGION}-docker.pkg.dev" --quiet
    ;;
  2)
    read -r -p "Docker Hub username: " DOCKER_USERNAME
    read -r -s -p "Docker Hub password / access token: " DOCKER_PASSWORD
    echo
    if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ]; then
      echo "ERROR: username and password are required"; exit 1
    fi
    DOCKER_USERNAME=$(echo "$DOCKER_USERNAME" | tr '[:upper:]' '[:lower:]')
    FULL_IMAGE_NAME="${DOCKER_USERNAME}/${IMAGE_NAME}:${IMAGE_TAG}"
    echo "Logging in to Docker Hub..."
    echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
    ;;
  *)
    echo "ERROR: invalid registry choice"; exit 1
    ;;
esac

echo "Building image: $FULL_IMAGE_NAME"
docker build -f Dockerfile -t "$FULL_IMAGE_NAME" .

echo "Pushing image: $FULL_IMAGE_NAME"
docker push "$FULL_IMAGE_NAME"

echo "Done. Image pushed: $FULL_IMAGE_NAME"
echo "Use this URI with scripts/deploy-image.sh"
