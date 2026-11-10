#!/bin/bash
set -e
set -o pipefail

# Run from the repository root: ./scripts/deploy-image.sh
APP_NAME="modresorts"
NAMESPACE="modresorts"

for tool in aws kubectl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool is not installed"; exit 1; }
done
[ -d kubernetes ] || { echo "ERROR: kubernetes/ directory not found. Run from the repository root."; exit 1; }

read -r -p "AWS region (e.g. us-east-1): " AWS_REGION
read -r -p "EKS cluster name: " CLUSTER_NAME
read -r -p "Docker image URI (registry/repo:tag): " IMAGE_URI
[ -z "$AWS_REGION" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$IMAGE_URI" ] && { echo "ERROR: region, cluster name and image URI are required"; exit 1; }

read -r -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
read -r -p "Enter value for SERVER_NAME (or press Enter to skip): " SERVER_NAME

# Escape characters special to sed replacement (| \ &)
esc() { printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'; }

# Render manifests in a temp copy so templates keep their placeholders
RENDER_DIR=$(mktemp -d)
trap 'rm -rf "$RENDER_DIR"' EXIT
cp kubernetes/*.yaml "$RENDER_DIR/"

sed -i.bak "s|{{IMAGE_URI}}|$(esc "$IMAGE_URI")|g" "$RENDER_DIR/deployment.yaml"
sed -i.bak "s|{{NAMESPACE}}|$NAMESPACE|g" "$RENDER_DIR"/*.yaml
sed -i.bak "s|{{WEATHER_API_KEY}}|$(esc "$WEATHER_API_KEY")|g" "$RENDER_DIR/deployment.yaml"
sed -i.bak "s|{{SERVER_NAME}}|$(esc "$SERVER_NAME")|g" "$RENDER_DIR/deployment.yaml"
rm -f "$RENDER_DIR"/*.bak

echo "Configuring kubectl for cluster $CLUSTER_NAME..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "ERROR: cannot reach cluster"; exit 1; }

echo "Applying manifests..."
kubectl apply -f "$RENDER_DIR/namespace.yaml"
kubectl apply -f "$RENDER_DIR/deployment.yaml"
kubectl apply -f "$RENDER_DIR/service.yaml"
kubectl apply -f "$RENDER_DIR/ingress.yaml"

echo "Waiting for rollout..."
if ! kubectl rollout status deployment/$APP_NAME -n $NAMESPACE --timeout=300s; then
  echo "ERROR: rollout failed. Roll back with:"
  echo "  kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
  exit 1
fi

kubectl get pods,svc,ingress -n $NAMESPACE

ALB_HOST=$(kubectl get ingress ${APP_NAME}-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
if [ -n "$ALB_HOST" ]; then
  echo "Application URL: http://$ALB_HOST"
else
  echo "Ingress address not yet assigned. Check later with: kubectl get ingress -n $NAMESPACE"
fi
echo "Rollback if needed: kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
