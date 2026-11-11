#!/bin/bash
# Build and push the ModResorts image. Run from the repository root:  ./scripts/build-push.sh
set -e
set -o pipefail

sanitize() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//'
}

if [ ! -f "Dockerfile" ]; then
  echo "ERROR: Dockerfile not found. Run this script from the repository root (./scripts/build-push.sh)."
  exit 1
fi

read -r -p "Project/image name [modresorts]: " PROJECT_NAME
PROJECT_NAME=${PROJECT_NAME:-modresorts}
IMAGE_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//;s/-*$//')
IMAGE_NAME=${IMAGE_NAME:-modresorts}

read -r -p "Image tag [latest]: " RAW_TAG
IMAGE_TAG=$(sanitize "$RAW_TAG")
IMAGE_TAG=${IMAGE_TAG:-latest}

echo ""
echo "Select registry:"
echo "  1. Google Artifact Registry"
echo "  2. Docker Hub"
read -r -p "Choice [1]: " REGISTRY_CHOICE
REGISTRY_CHOICE=${REGISTRY_CHOICE:-1}

case "$REGISTRY_CHOICE" in
  1)
    read -r -p "GCP project ID: " GCP_PROJECT
    read -r -p "Artifact Registry region [us-central1]: " GCP_REGION
    GCP_REGION=${GCP_REGION:-us-central1}
    read -r -p "Artifact Registry repository [modresorts]: " AR_REPO
    AR_REPO=${AR_REPO:-modresorts}
    if [ -z "$GCP_PROJECT" ]; then echo "ERROR: GCP project ID is required."; exit 1; fi
    FULL_IMAGE_NAME="${GCP_REGION}-docker.pkg.dev/${GCP_PROJECT}/${AR_REPO}/${IMAGE_NAME}:${IMAGE_TAG}"
    echo "Authenticating with Google Cloud..."
    if ! gcloud auth print-access-token >/dev/null 2>&1; then
      gcloud auth login
    fi
    gcloud config set project "$GCP_PROJECT"
    gcloud auth configure-docker "${GCP_REGION}-docker.pkg.dev" --quiet
    ;;
  2)
    read -r -p "Docker Hub username: " DOCKER_USERNAME
    read -r -s -p "Docker Hub password/token: " DOCKER_PASSWORD
    echo ""
    if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ]; then echo "ERROR: Docker Hub credentials are required."; exit 1; fi
    DOCKER_USER_LC=$(echo "$DOCKER_USERNAME" | tr '[:upper:]' '[:lower:]')
    FULL_IMAGE_NAME="${DOCKER_USER_LC}/${IMAGE_NAME}:${IMAGE_TAG}"
    echo "Logging in to Docker Hub..."
    echo "$DOCKER_PASSWORD" | docker login --username "$DOCKER_USERNAME" --password-stdin
    ;;
  *)
    echo "ERROR: Invalid choice."
    exit 1
    ;;
esac

echo ""
echo "Building image: $FULL_IMAGE_NAME"
docker build -f Dockerfile -t "$FULL_IMAGE_NAME" .

echo "Pushing image: $FULL_IMAGE_NAME"
docker push "$FULL_IMAGE_NAME"

echo ""
echo "SUCCESS: image pushed -> $FULL_IMAGE_NAME"
echo "Deploy with: ./scripts/deploy-image.sh (use the image URI above)"
