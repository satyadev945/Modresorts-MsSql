#!/bin/bash
set -e
set -o pipefail

# Run from repository root: ./scripts/deploy-image.sh
APP_NAME="modresorts"
NAMESPACE="modresorts"
SRC_DIR="kubernetes"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

for cmd in az kubectl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd is required but not installed"; exit 1; }
done

read -r -p "Enter Azure resource group: " RESOURCE_GROUP
read -r -p "Enter AKS cluster name: " CLUSTER_NAME
read -r -p "Enter Docker image URI (e.g. myacr.azurecr.io/modresorts:latest): " IMAGE_URI
if [ -z "$RESOURCE_GROUP" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$IMAGE_URI" ]; then
  echo "ERROR: resource group, cluster name and image URI are required"; exit 1
fi

read -r -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
read -r -p "Enter value for SERVER_DISPLAY_NAME (or press Enter to skip): " SERVER_DISPLAY_NAME
read -r -p "Enter value for WEATHER_SERVICE_GRPC_ENDPOINT (or press Enter to skip): " WEATHER_SERVICE_GRPC_ENDPOINT

# Work on copies so the template manifests keep their placeholders
cp "$SRC_DIR"/*.yaml "$WORK_DIR"/
for f in "$WORK_DIR"/*.yaml; do
  sed -i.bak \
    -e "s|{{IMAGE_URI}}|$IMAGE_URI|g" \
    -e "s|{{NAMESPACE}}|$NAMESPACE|g" \
    -e "s|{{WEATHER_API_KEY}}|$WEATHER_API_KEY|g" \
    -e "s|{{SERVER_DISPLAY_NAME}}|$SERVER_DISPLAY_NAME|g" \
    -e "s|{{WEATHER_SERVICE_GRPC_ENDPOINT}}|$WEATHER_SERVICE_GRPC_ENDPOINT|g" "$f"
  rm -f "$f.bak"
done

echo "Configuring kubectl for $CLUSTER_NAME ..."
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

echo "Verifying cluster connectivity ..."
kubectl cluster-info || { echo "ERROR: cannot reach cluster"; exit 1; }

echo "Applying manifests ..."
kubectl apply -f "$WORK_DIR/namespace.yaml"
kubectl apply -f "$WORK_DIR/deployment.yaml"
kubectl apply -f "$WORK_DIR/service.yaml"
kubectl apply -f "$WORK_DIR/ingress.yaml"

echo "Waiting for rollout ..."
if ! kubectl rollout status deployment/$APP_NAME -n $NAMESPACE --timeout=300s; then
  echo "ERROR: rollout failed. To roll back run:"
  echo "  kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
  exit 1
fi

kubectl get pods,svc,ingress -n $NAMESPACE

INGRESS_IP=$(kubectl get ingress ${APP_NAME}-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [ -n "$INGRESS_IP" ]; then
  echo "Application URL: http://$INGRESS_IP/ (host header: modresorts.example.com)"
else
  echo "Ingress address not yet assigned. Check: kubectl get ingress -n $NAMESPACE"
  echo "Or port-forward: kubectl port-forward svc/${APP_NAME}-service 8080:80 -n $NAMESPACE"
fi
echo "Rollback if needed: kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
