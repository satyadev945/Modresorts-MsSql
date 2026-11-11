#!/bin/bash
# Deploy ModResorts to GKE. Run from the repository root.
set -e
set -o pipefail

APP_NAME="modresorts"
NAMESPACE="modresorts"

for cmd in gcloud kubectl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd is not installed"; exit 1; }
done

read -r -p "GCP project ID: " GCP_PROJECT
read -r -p "GKE cluster zone/region (e.g. us-central1-a): " GCP_ZONE
read -r -p "GKE cluster name: " CLUSTER_NAME
read -r -p "Docker image URI (registry/path:tag): " IMAGE_URI
for v in GCP_PROJECT GCP_ZONE CLUSTER_NAME IMAGE_URI; do
  if [ -z "${!v}" ]; then echo "ERROR: $v is required"; exit 1; fi
done

read -r -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
read -r -p "Enter value for REMOTE_SERVICE_GRPC_TARGET (or press Enter to skip): " REMOTE_SERVICE_GRPC_TARGET
read -r -p "Enter value for SERVER_NAME (or press Enter for $APP_NAME): " SERVER_NAME
SERVER_NAME=${SERVER_NAME:-$APP_NAME}

# Escape characters special to sed replacement (\ | &)
esc() { printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'; }

# Work on a temporary copy so the template manifests stay untouched
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp kubernetes/*.yaml "$WORK_DIR/"

sed -i.bak "s|{{IMAGE_URI}}|$(esc "$IMAGE_URI")|g" "$WORK_DIR/deployment.yaml"
sed -i.bak "s|{{NAMESPACE}}|$(esc "$NAMESPACE")|g" "$WORK_DIR"/*.yaml
sed -i.bak "s|{{WEATHER_API_KEY}}|$(esc "$WEATHER_API_KEY")|g" "$WORK_DIR/deployment.yaml"
sed -i.bak "s|{{REMOTE_SERVICE_GRPC_TARGET}}|$(esc "$REMOTE_SERVICE_GRPC_TARGET")|g" "$WORK_DIR/deployment.yaml"
sed -i.bak "s|{{SERVER_NAME}}|$(esc "$SERVER_NAME")|g" "$WORK_DIR/deployment.yaml"
rm -f "$WORK_DIR"/*.bak

echo "Configuring kubectl..."
gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$GCP_ZONE" --project "$GCP_PROJECT"

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

echo "Waiting for ingress address (can take several minutes on GKE)..."
for i in $(seq 1 30); do
  ADDR=$(kubectl get ingress ${APP_NAME}-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [ -n "$ADDR" ] && break
  sleep 10
done
if [ -n "$ADDR" ]; then
  echo "Application URL: http://$ADDR/"
else
  echo "Ingress address not assigned yet. Check: kubectl get ingress -n $NAMESPACE"
fi
echo "Rollback if needed: kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
