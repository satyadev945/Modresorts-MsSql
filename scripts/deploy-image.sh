#!/bin/bash
# Deploy ModResorts to Azure AKS. Run from the repository root.
set -e
set -o pipefail

APP_NAME="modresorts"
NAMESPACE="modresorts"

echo "=== ModResorts AKS deployment ==="

read -r -p "Azure resource group: " RESOURCE_GROUP
read -r -p "AKS cluster name: " CLUSTER_NAME
read -r -p "Docker image URI (registry/image:tag): " IMAGE_URI

if [ -z "$RESOURCE_GROUP" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$IMAGE_URI" ]; then
  echo "Resource group, cluster name and image URI are required"
  exit 1
fi

read -r -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
read -r -p "Enter value for ENABLE_JMX_APPINFO [true]: " ENABLE_JMX_APPINFO
ENABLE_JMX_APPINFO=${ENABLE_JMX_APPINFO:-true}
read -r -p "Enter value for SERVER_NAME (or press Enter to skip): " SERVER_NAME

# Escape characters special to sed replacement (\ | &)
esc() { printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'; }

# Work on a copy so the template manifests stay untouched
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp kubernetes/*.yaml "$WORK_DIR/"

sed -i "s|{{IMAGE_URI}}|$(esc "$IMAGE_URI")|g" "$WORK_DIR/deployment.yaml"
sed -i "s|{{NAMESPACE}}|$NAMESPACE|g" "$WORK_DIR"/*.yaml
sed -i "s|{{WEATHER_API_KEY}}|$(esc "$WEATHER_API_KEY")|g" "$WORK_DIR/deployment.yaml"
sed -i "s|{{ENABLE_JMX_APPINFO}}|$(esc "$ENABLE_JMX_APPINFO")|g" "$WORK_DIR/deployment.yaml"
sed -i "s|{{SERVER_NAME}}|$(esc "$SERVER_NAME")|g" "$WORK_DIR/deployment.yaml"

echo "Configuring kubectl..."
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "Cannot reach cluster"; exit 1; }

echo "Applying manifests..."
kubectl apply -f "$WORK_DIR/namespace.yaml"
kubectl apply -f "$WORK_DIR/deployment.yaml"
kubectl apply -f "$WORK_DIR/service.yaml"
kubectl apply -f "$WORK_DIR/ingress.yaml"

echo "Waiting for rollout..."
if ! kubectl rollout status deployment/$APP_NAME -n $NAMESPACE --timeout=300s; then
  echo "Rollout failed. To roll back run:"
  echo "  kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
  exit 1
fi

kubectl get pods,svc,ingress -n $NAMESPACE

INGRESS_IP=$(kubectl get ingress modresorts-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [ -n "$INGRESS_IP" ]; then
  echo "Application URL: http://$INGRESS_IP/ (host header: modresorts.example.com)"
else
  echo "Ingress address not assigned yet. Check: kubectl get ingress -n $NAMESPACE"
fi
echo "Rollback if needed: kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
