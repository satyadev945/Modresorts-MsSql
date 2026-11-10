#!/bin/bash
set -e
set -o pipefail

APP_NAME="modresorts"
NAMESPACE="modresorts"

read -r -p "Enter Azure resource group: " RESOURCE_GROUP
[ -z "$RESOURCE_GROUP" ] && { echo "Resource group is required"; exit 1; }
read -r -p "Enter AKS cluster name: " CLUSTER_NAME
[ -z "$CLUSTER_NAME" ] && { echo "Cluster name is required"; exit 1; }
read -r -p "Enter full Docker image URI (registry/name:tag): " IMAGE_URI
[ -z "$IMAGE_URI" ] && { echo "Image URI is required"; exit 1; }

read -r -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
read -r -p "Enter value for SERVER_NAME (or press Enter to skip): " SERVER_NAME

# Work on a temporary copy so the templates keep their placeholders
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp kubernetes/*.yaml "$WORK_DIR/"

sed -i 's|{{IMAGE_URI}}|'"$IMAGE_URI"'|g' "$WORK_DIR"/*.yaml
sed -i 's|{{NAMESPACE}}|'"$NAMESPACE"'|g' "$WORK_DIR"/*.yaml
sed -i 's|{{WEATHER_API_KEY}}|'"$WEATHER_API_KEY"'|g' "$WORK_DIR"/*.yaml
sed -i 's|{{SERVER_NAME}}|'"$SERVER_NAME"'|g' "$WORK_DIR"/*.yaml

echo "Configuring kubectl for $CLUSTER_NAME ..."
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

echo "Verifying cluster connectivity ..."
kubectl cluster-info || exit 1

echo "Applying manifests ..."
kubectl apply -f "$WORK_DIR/namespace.yaml"
kubectl apply -f "$WORK_DIR/deployment.yaml"
kubectl apply -f "$WORK_DIR/service.yaml"
kubectl apply -f "$WORK_DIR/ingress.yaml"

echo "Waiting for rollout ..."
if ! kubectl rollout status deployment/$APP_NAME -n $NAMESPACE --timeout=300s; then
  echo "Rollout failed. To roll back: kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
  exit 1
fi

kubectl get pods,svc,ingress -n $NAMESPACE

INGRESS_IP=$(kubectl get ingress ${APP_NAME}-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [ -n "$INGRESS_IP" ]; then
  echo "Application URL: http://$INGRESS_IP/ (host header: modresorts.example.com)"
else
  echo "Ingress address not yet assigned. Check: kubectl get ingress -n $NAMESPACE"
fi
echo "Rollback if needed: kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
