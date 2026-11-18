#!/bin/bash
set -e
set -o pipefail

# Run from the repository root:  ./scripts/deploy-image.sh
APP_NAME="modresorts"

echo "=== ModResorts deployment to AWS EKS ==="

read -r -p "Enter AWS region (e.g. us-east-1): " AWS_REGION
read -r -p "Enter EKS cluster name: " CLUSTER_NAME
read -r -p "Enter Docker image URI (registry/repo:tag): " IMAGE_URI
read -r -p "Enter Kubernetes namespace (default: $APP_NAME): " NAMESPACE
NAMESPACE=${NAMESPACE:-$APP_NAME}

if [ -z "$AWS_REGION" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$IMAGE_URI" ]; then
  echo "ERROR: AWS region, cluster name and image URI are required"; exit 1
fi

echo "Optional application settings (press Enter to skip)"
read -r -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
read -r -p "Enter value for REDIS_HOST (or press Enter to skip): " REDIS_HOST
read -r -p "Enter value for REDIS_PORT (default 6379): " REDIS_PORT
REDIS_PORT=${REDIS_PORT:-6379}
read -r -s -p "Enter value for REDIS_PASSWORD (or press Enter to skip): " REDIS_PASSWORD
echo
read -r -p "Enter value for REDIS_CACHE_TTL_SECONDS (default 60): " REDIS_CACHE_TTL_SECONDS
REDIS_CACHE_TTL_SECONDS=${REDIS_CACHE_TTL_SECONDS:-60}
read -r -p "Enter value for JNDI_INITIAL_CONTEXT_FACTORY (or press Enter to skip): " JNDI_INITIAL_CONTEXT_FACTORY
read -r -p "Enter value for JNDI_PROVIDER_URL (or press Enter to skip): " JNDI_PROVIDER_URL

# Work on a temporary copy so the template manifests keep their placeholders
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp kubernetes/*.yaml "$WORK_DIR"/

# Escape characters that are special in a sed replacement using the pipe delimiter
esc() { printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'; }

replace() {
  sed -i "s|{{$1}}|$(esc "$2")|g" "$WORK_DIR"/*.yaml
}

replace IMAGE_URI "$IMAGE_URI"
replace NAMESPACE "$NAMESPACE"
replace WEATHER_API_KEY "$WEATHER_API_KEY"
replace REDIS_HOST "$REDIS_HOST"
replace REDIS_PORT "$REDIS_PORT"
replace REDIS_PASSWORD "$REDIS_PASSWORD"
replace REDIS_CACHE_TTL_SECONDS "$REDIS_CACHE_TTL_SECONDS"
replace JNDI_INITIAL_CONTEXT_FACTORY "$JNDI_INITIAL_CONTEXT_FACTORY"
replace JNDI_PROVIDER_URL "$JNDI_PROVIDER_URL"

echo "Configuring kubectl for cluster $CLUSTER_NAME..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "ERROR: cannot reach the cluster"; exit 1; }

echo "Applying Kubernetes manifests..."
kubectl apply -f "$WORK_DIR/namespace.yaml"
kubectl apply -f "$WORK_DIR/deployment.yaml"
kubectl apply -f "$WORK_DIR/service.yaml"
kubectl apply -f "$WORK_DIR/ingress.yaml"

echo "Waiting for rollout..."
if ! kubectl rollout status deployment/$APP_NAME -n "$NAMESPACE" --timeout=300s; then
  echo "ERROR: rollout failed. To roll back run:"
  echo "  kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
  echo "To inspect: kubectl describe pods -n $NAMESPACE ; kubectl logs deployment/$APP_NAME -n $NAMESPACE"
  exit 1
fi

echo "Deployed resources:"
kubectl get pods,svc,ingress -n "$NAMESPACE"

INGRESS_HOST=$(kubectl get ingress ${APP_NAME}-ingress -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
if [ -n "$INGRESS_HOST" ]; then
  echo "Application URL: http://$INGRESS_HOST"
else
  echo "Ingress address not yet assigned. Check later with:"
  echo "  kubectl get ingress ${APP_NAME}-ingress -n $NAMESPACE"
  echo "Requires the AWS Load Balancer Controller installed in the cluster."
fi

echo "Rollback if needed: kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
