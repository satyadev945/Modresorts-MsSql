#!/bin/bash
# Deploy ModResorts to AWS EKS. Run from the repository root.
set -e
set -o pipefail

APP_NAME="modresorts"
NAMESPACE="modresorts"

echo "=== ModResorts - Deploy to AWS EKS ==="

read -r -p "AWS region (e.g. us-east-1): " AWS_REGION
read -r -p "EKS cluster name: " CLUSTER_NAME
read -r -p "Docker image URI (registry/repo:tag): " IMAGE_URI
if [ -z "$AWS_REGION" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$IMAGE_URI" ]; then
  echo "AWS region, cluster name and image URI are required"; exit 1
fi

read -r -p "Enter value for REDIS_HOST (or press Enter for 'localhost'): " REDIS_HOST
read -r -p "Enter value for REDIS_PORT (or press Enter for '6379'): " REDIS_PORT
read -r -p "Enter value for REDIS_CACHE_TTL (or press Enter for '300'): " REDIS_CACHE_TTL
read -r -s -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
echo
REDIS_HOST=${REDIS_HOST:-localhost}
REDIS_PORT=${REDIS_PORT:-6379}
REDIS_CACHE_TTL=${REDIS_CACHE_TTL:-300}

# Render manifests into a temp dir so the templates stay untouched
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp kubernetes/*.yaml "$WORK_DIR"/

esc() { printf '%s' "$1" | sed 's/[&|\\]/\\&/g'; }

sed -i 's|{{IMAGE_URI}}|'"$(esc "$IMAGE_URI")"'|g' "$WORK_DIR/deployment.yaml"
sed -i 's|{{REDIS_HOST}}|'"$(esc "$REDIS_HOST")"'|g' "$WORK_DIR/deployment.yaml"
sed -i 's|{{REDIS_PORT}}|'"$(esc "$REDIS_PORT")"'|g' "$WORK_DIR/deployment.yaml"
sed -i 's|{{REDIS_CACHE_TTL}}|'"$(esc "$REDIS_CACHE_TTL")"'|g' "$WORK_DIR/deployment.yaml"
sed -i 's|{{WEATHER_API_KEY}}|'"$(esc "$WEATHER_API_KEY")"'|g' "$WORK_DIR/deployment.yaml"

echo "Configuring kubectl..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "Cannot reach cluster"; exit 1; }

echo "Applying manifests..."
kubectl apply -f "$WORK_DIR/namespace.yaml"
kubectl apply -f "$WORK_DIR/deployment.yaml"
kubectl apply -f "$WORK_DIR/service.yaml"
kubectl apply -f "$WORK_DIR/ingress.yaml"

echo "Waiting for rollout..."
if ! kubectl rollout status deployment/${APP_NAME} -n ${NAMESPACE} --timeout=300s; then
  echo "Rollout failed. To roll back run:"
  echo "  kubectl rollout undo deployment/${APP_NAME} -n ${NAMESPACE}"
  echo "Inspect with: kubectl describe pods -n ${NAMESPACE} ; kubectl logs -l app=${APP_NAME} -n ${NAMESPACE}"
  exit 1
fi

kubectl get pods,svc,ingress -n ${NAMESPACE}

INGRESS_HOST=$(kubectl get ingress ${APP_NAME}-ingress -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
if [ -n "$INGRESS_HOST" ]; then
  echo "Application URL: http://${INGRESS_HOST}"
else
  echo "Ingress address not yet assigned (requires AWS Load Balancer Controller). Check: kubectl get ingress -n ${NAMESPACE}"
fi
echo "Rollback if needed: kubectl rollout undo deployment/${APP_NAME} -n ${NAMESPACE}"
