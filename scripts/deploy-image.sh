#!/bin/bash
set -e
set -o pipefail

APP_NAME="modresorts"
NAMESPACE="modresorts"

echo "=== ModResorts - Deploy to Azure AKS ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
K8S_SRC="$SCRIPT_DIR/../kubernetes"

read -r -p "Enter Azure resource group: " RESOURCE_GROUP
if [ -z "$RESOURCE_GROUP" ]; then echo "Resource group is required"; exit 1; fi
read -r -p "Enter AKS cluster name: " CLUSTER_NAME
if [ -z "$CLUSTER_NAME" ]; then echo "AKS cluster name is required"; exit 1; fi
read -r -p "Enter Docker image URI (e.g. myacr.azurecr.io/modresorts:latest): " IMAGE_URI
if [ -z "$IMAGE_URI" ]; then echo "Image URI is required"; exit 1; fi

read -r -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
read -r -p "Enter value for WEATHER_JMX_ENABLED [false]: " WEATHER_JMX_ENABLED
WEATHER_JMX_ENABLED=${WEATHER_JMX_ENABLED:-false}

# Work on a temporary copy so the template manifests stay untouched
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
cp -r "$K8S_SRC"/. "$WORK_DIR"/

sed -i.bak "s|{{IMAGE_URI}}|$IMAGE_URI|g" "$WORK_DIR/deployment.yaml"
sed -i.bak "s|{{NAMESPACE}}|$NAMESPACE|g" "$WORK_DIR"/*.yaml
sed -i.bak "s|{{WEATHER_API_KEY}}|$WEATHER_API_KEY|g" "$WORK_DIR/deployment.yaml"
sed -i.bak "s|{{WEATHER_JMX_ENABLED}}|$WEATHER_JMX_ENABLED|g" "$WORK_DIR/deployment.yaml"
rm -f "$WORK_DIR"/*.bak

echo "Configuring kubectl for cluster $CLUSTER_NAME ..."
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

echo "Verifying cluster connectivity ..."
kubectl cluster-info || { echo "Cannot reach cluster"; exit 1; }

echo "Applying manifests ..."
kubectl apply -f "$WORK_DIR/namespace.yaml"
kubectl apply -f "$WORK_DIR/deployment.yaml"
kubectl apply -f "$WORK_DIR/service.yaml"
kubectl apply -f "$WORK_DIR/ingress.yaml"

echo "Waiting for rollout ..."
if ! kubectl rollout status deployment/$APP_NAME -n $NAMESPACE --timeout=300s; then
  echo "Rollout failed. To roll back run:"
  echo "  kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
  exit 1
fi

echo "Resources:"
kubectl get pods,svc,ingress -n $NAMESPACE

INGRESS_IP=$(kubectl get ingress ${APP_NAME}-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [ -n "$INGRESS_IP" ]; then
  echo "Application URL: http://$INGRESS_IP/ (host header: modresorts.example.com)"
else
  echo "Ingress address not yet assigned. Check: kubectl get ingress -n $NAMESPACE"
fi
echo "Rollback if needed: kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
