#!/bin/bash
# Deploy ModResorts to AWS EKS. Run from the repository root.
set -e
set -o pipefail

APP_NAME="modresorts"
NAMESPACE="modresorts"

for cmd in aws kubectl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd is not installed"; exit 1; }
done

read -r -p "AWS region (e.g. us-east-1): " AWS_REGION
read -r -p "EKS cluster name: " CLUSTER_NAME
read -r -p "Docker image URI (registry/repo:tag): " IMAGE_URI
if [ -z "$AWS_REGION" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$IMAGE_URI" ]; then
  echo "ERROR: region, cluster name and image URI are required"; exit 1
fi

read -r -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
read -r -p "Enter value for JNDI_INITIAL_CONTEXT_FACTORY (or press Enter to skip): " JNDI_INITIAL_CONTEXT_FACTORY
read -r -p "Enter value for JNDI_PROVIDER_URL (or press Enter to skip): " JNDI_PROVIDER_URL
read -r -p "Enter value for SERVER_NAME (or press Enter for '$APP_NAME'): " SERVER_NAME
SERVER_NAME=${SERVER_NAME:-$APP_NAME}

# Escape characters special to sed replacement (\ & |)
esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

# Work on a temporary copy so the template manifests remain untouched
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp kubernetes/*.yaml "$WORK_DIR"/

sed -i 's|{{IMAGE_URI}}|'"$(esc "$IMAGE_URI")"'|g' "$WORK_DIR"/*.yaml
sed -i 's|{{NAMESPACE}}|'"$NAMESPACE"'|g' "$WORK_DIR"/*.yaml
sed -i 's|{{WEATHER_API_KEY}}|'"$(esc "$WEATHER_API_KEY")"'|g' "$WORK_DIR"/*.yaml
sed -i 's|{{JNDI_INITIAL_CONTEXT_FACTORY}}|'"$(esc "$JNDI_INITIAL_CONTEXT_FACTORY")"'|g' "$WORK_DIR"/*.yaml
sed -i 's|{{JNDI_PROVIDER_URL}}|'"$(esc "$JNDI_PROVIDER_URL")"'|g' "$WORK_DIR"/*.yaml
sed -i 's|{{SERVER_NAME}}|'"$(esc "$SERVER_NAME")"'|g' "$WORK_DIR"/*.yaml

echo ">>> Configuring kubectl for cluster $CLUSTER_NAME..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo ">>> Verifying cluster connectivity..."
kubectl cluster-info || { echo "ERROR: cannot reach cluster"; exit 1; }

echo ">>> Applying manifests..."
kubectl apply -f "$WORK_DIR/namespace.yaml"
kubectl apply -f "$WORK_DIR/deployment.yaml"
kubectl apply -f "$WORK_DIR/service.yaml"
kubectl apply -f "$WORK_DIR/ingress.yaml"

echo ">>> Waiting for rollout..."
if ! kubectl rollout status deployment/$APP_NAME -n $NAMESPACE --timeout=300s; then
  echo "ERROR: rollout failed. Roll back with:"
  echo "  kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
  echo "Inspect with: kubectl describe pods -n $NAMESPACE ; kubectl logs -l app=$APP_NAME -n $NAMESPACE"
  exit 1
fi

kubectl get pods,svc,ingress -n $NAMESPACE

INGRESS_HOST=$(kubectl get ingress ${APP_NAME}-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
if [ -n "$INGRESS_HOST" ]; then
  echo "Application URL: http://$INGRESS_HOST/"
else
  echo "Ingress address not yet assigned. Check: kubectl get ingress -n $NAMESPACE"
fi
echo "Rollback if needed: kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
