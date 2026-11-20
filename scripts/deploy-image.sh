#!/bin/bash
# Deploy ModResorts to AWS EKS. Run from the repository root.
set -e
set -o pipefail

APP_NAME="modresorts"
NAMESPACE="modresorts"

echo "=== ModResorts: deploy to AWS EKS ==="

read -r -p "Enter AWS region (e.g. us-east-1): " AWS_REGION
read -r -p "Enter EKS cluster name: " CLUSTER_NAME
read -r -p "Enter Docker image URI (registry/repo:tag): " IMAGE_URI

if [ -z "$AWS_REGION" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$IMAGE_URI" ]; then
  echo "ERROR: AWS region, cluster name and image URI are required."; exit 1
fi

echo "Optional application settings (press Enter to skip)"
read -r -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
read -r -p "Enter value for SERVER_NAME (or press Enter to skip): " SERVER_NAME
read -r -p "Enter value for JNDI_INITIAL_CONTEXT_FACTORY (or press Enter to skip): " JNDI_INITIAL_CONTEXT_FACTORY
read -r -p "Enter value for JNDI_PROVIDER_URL (or press Enter to skip): " JNDI_PROVIDER_URL

# Work on a temporary copy so the template manifests stay untouched
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp kubernetes/*.yaml "$WORK_DIR/"

for f in "$WORK_DIR"/*.yaml; do
  sed -i.bak \
    -e 's|{{IMAGE_URI}}|'"$IMAGE_URI"'|g' \
    -e 's|{{NAMESPACE}}|'"$NAMESPACE"'|g' \
    -e 's|{{WEATHER_API_KEY}}|'"$WEATHER_API_KEY"'|g' \
    -e 's|{{SERVER_NAME}}|'"$SERVER_NAME"'|g' \
    -e 's|{{JNDI_INITIAL_CONTEXT_FACTORY}}|'"$JNDI_INITIAL_CONTEXT_FACTORY"'|g' \
    -e 's|{{JNDI_PROVIDER_URL}}|'"$JNDI_PROVIDER_URL"'|g' \
    "$f"
  rm -f "$f.bak"
done

echo "Configuring kubectl..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "ERROR: cannot reach cluster"; exit 1; }

echo "Applying manifests..."
kubectl apply -f "$WORK_DIR/namespace.yaml"
kubectl apply -f "$WORK_DIR/deployment.yaml"
kubectl apply -f "$WORK_DIR/service.yaml"
kubectl apply -f "$WORK_DIR/ingress.yaml"

echo "Waiting for rollout..."
if ! kubectl rollout status deployment/$APP_NAME -n $NAMESPACE --timeout=300s; then
  echo "ERROR: rollout failed. To roll back run:"
  echo "  kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
  exit 1
fi

kubectl get pods,svc,ingress -n $NAMESPACE

INGRESS_HOST=$(kubectl get ingress ${APP_NAME}-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
if [ -n "$INGRESS_HOST" ]; then
  echo "Application URL: http://$INGRESS_HOST/"
else
  echo "Ingress address not yet assigned. Check later with: kubectl get ingress -n $NAMESPACE"
fi
echo "Rollback if needed: kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
