#!/bin/bash
set -e
set -o pipefail

# Run from the repository root:  ./scripts/deploy-image.sh
APP_NAME="modresorts"
DEFAULT_NAMESPACE="modresorts"
DEFAULT_HOST="modresorts.example.com"

echo "=== ModResorts: deploy to AWS EKS ==="

for tool in aws kubectl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool is not installed or not in PATH"; exit 1; }
done

read -r -p "Enter AWS region (e.g. us-east-1): " AWS_REGION
[ -n "$AWS_REGION" ] || { echo "ERROR: AWS region is required"; exit 1; }
read -r -p "Enter EKS cluster name: " CLUSTER_NAME
[ -n "$CLUSTER_NAME" ] || { echo "ERROR: EKS cluster name is required"; exit 1; }
read -r -p "Enter Docker image URI (registry/repo:tag): " IMAGE_URI
[ -n "$IMAGE_URI" ] || { echo "ERROR: Image URI is required"; exit 1; }
read -r -p "Enter Kubernetes namespace [$DEFAULT_NAMESPACE]: " NAMESPACE
NAMESPACE=${NAMESPACE:-$DEFAULT_NAMESPACE}
read -r -p "Enter ingress host name [$DEFAULT_HOST]: " INGRESS_HOST
INGRESS_HOST=${INGRESS_HOST:-$DEFAULT_HOST}
read -r -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY

# Work on a temporary copy so the template manifests stay untouched
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp kubernetes/*.yaml "$WORK_DIR/"

# Escape characters that are special in sed replacement strings (& | \)
esc() { printf '%s' "$1" | sed -e 's/[&|\\]/\\&/g'; }

for f in "$WORK_DIR"/*.yaml; do
  sed -i.bak \
    -e "s|{{IMAGE_URI}}|$(esc "$IMAGE_URI")|g" \
    -e "s|{{NAMESPACE}}|$(esc "$NAMESPACE")|g" \
    -e "s|{{INGRESS_HOST}}|$(esc "$INGRESS_HOST")|g" \
    -e "s|{{WEATHER_API_KEY}}|$(esc "$WEATHER_API_KEY")|g" \
    "$f"
  rm -f "$f.bak"
done

echo ">>> Configuring kubectl for cluster $CLUSTER_NAME..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo ">>> Verifying cluster connectivity..."
kubectl cluster-info || { echo "ERROR: cannot reach the cluster"; exit 1; }

echo ">>> Applying manifests..."
kubectl apply -f "$WORK_DIR/namespace.yaml"
kubectl apply -f "$WORK_DIR/deployment.yaml"
kubectl apply -f "$WORK_DIR/service.yaml"
kubectl apply -f "$WORK_DIR/ingress.yaml"

echo ">>> Waiting for rollout..."
if ! kubectl rollout status deployment/$APP_NAME -n "$NAMESPACE" --timeout=300s; then
  echo "ERROR: rollout failed. To roll back run:"
  echo "  kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
  echo "Inspect with: kubectl describe pods -n $NAMESPACE ; kubectl logs deployment/$APP_NAME -n $NAMESPACE"
  exit 1
fi

echo ">>> Resources in namespace $NAMESPACE:"
kubectl get pods,svc,ingress -n "$NAMESPACE"

INGRESS_ADDR=$(kubectl get ingress ${APP_NAME}-ingress -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
if [ -n "$INGRESS_ADDR" ]; then
  echo "Application URL: http://$INGRESS_ADDR/  (Host header: $INGRESS_HOST)"
else
  echo "Ingress address not yet assigned. Check later with: kubectl get ingress -n $NAMESPACE"
fi
echo "Rollback if needed: kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
