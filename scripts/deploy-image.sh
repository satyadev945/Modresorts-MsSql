#!/bin/bash
set -e
set -o pipefail

# Run from repository root: ./scripts/deploy-image.sh
APP_NAME="modresorts"
DEFAULT_NAMESPACE="modresorts"

command -v az >/dev/null 2>&1 || { echo "Azure CLI (az) is required"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required"; exit 1; }

read -r -p "Enter Azure resource group: " RESOURCE_GROUP
read -r -p "Enter AKS cluster name: " CLUSTER_NAME
read -r -p "Enter Docker image URI (e.g. myacr.azurecr.io/${APP_NAME}:latest): " IMAGE_URI
if [ -z "$RESOURCE_GROUP" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$IMAGE_URI" ]; then
  echo "Resource group, cluster name and image URI are required"; exit 1
fi
read -r -p "Enter Kubernetes namespace [${DEFAULT_NAMESPACE}]: " NAMESPACE
NAMESPACE=${NAMESPACE:-$DEFAULT_NAMESPACE}
read -r -p "Enter ingress host [${APP_NAME}.example.com]: " INGRESS_HOST
INGRESS_HOST=${INGRESS_HOST:-${APP_NAME}.example.com}
read -r -s -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
echo ""

# Escape characters special to sed replacement text
esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

# Work on a temporary copy so the template manifests stay untouched
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp kubernetes/*.yaml "$WORK_DIR/"

sed -i 's|{{IMAGE_URI}}|'"$(esc "$IMAGE_URI")"'|g' "$WORK_DIR"/*.yaml
sed -i 's|{{NAMESPACE}}|'"$(esc "$NAMESPACE")"'|g' "$WORK_DIR"/*.yaml
sed -i 's|{{INGRESS_HOST}}|'"$(esc "$INGRESS_HOST")"'|g' "$WORK_DIR"/*.yaml
sed -i 's|{{WEATHER_API_KEY}}|'"$(esc "$WEATHER_API_KEY")"'|g' "$WORK_DIR"/*.yaml

echo "Configuring kubectl for $CLUSTER_NAME ..."
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

echo "Verifying cluster connectivity ..."
kubectl cluster-info || { echo "Cannot reach cluster"; exit 1; }

echo "Applying manifests ..."
kubectl apply -f "$WORK_DIR/namespace.yaml"
kubectl apply -f "$WORK_DIR/deployment.yaml"
kubectl apply -f "$WORK_DIR/service.yaml"
kubectl apply -f "$WORK_DIR/ingress.yaml"

echo "Waiting for rollout ..."
if ! kubectl rollout status deployment/${APP_NAME} -n "$NAMESPACE" --timeout=300s; then
  echo "Rollout failed. To roll back run:"
  echo "  kubectl rollout undo deployment/${APP_NAME} -n $NAMESPACE"
  echo "Inspect with: kubectl describe pods -n $NAMESPACE ; kubectl logs deployment/${APP_NAME} -n $NAMESPACE"
  exit 1
fi

kubectl get pods,svc,ingress -n "$NAMESPACE"

INGRESS_IP=$(kubectl get ingress ${APP_NAME}-ingress -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
echo ""
echo "Deployment complete."
if [ -n "$INGRESS_IP" ]; then
  echo "Application URL: http://${INGRESS_IP}/  (Host: ${INGRESS_HOST})"
else
  echo "Ingress address not yet assigned. Check: kubectl get ingress -n $NAMESPACE"
fi
echo "Host URL: http://${INGRESS_HOST}/"
echo "Rollback: kubectl rollout undo deployment/${APP_NAME} -n $NAMESPACE"
