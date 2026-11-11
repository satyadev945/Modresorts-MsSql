#!/bin/bash
set -e
set -o pipefail

# Run from repository root: ./scripts/deploy-image.sh
APP_NAME="modresorts"
NAMESPACE="modresorts"

echo "=== ModResorts - Deploy to Azure AKS ==="

read -r -p "Enter Azure resource group: " RESOURCE_GROUP
if [ -z "$RESOURCE_GROUP" ]; then echo "Resource group is required"; exit 1; fi
read -r -p "Enter AKS cluster name: " CLUSTER_NAME
if [ -z "$CLUSTER_NAME" ]; then echo "AKS cluster name is required"; exit 1; fi
read -r -p "Enter Docker image URI (e.g. myacr.azurecr.io/modresorts:latest): " IMAGE_URI
if [ -z "$IMAGE_URI" ]; then echo "Image URI is required"; exit 1; fi

read -r -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
read -r -p "Enter value for JMX_APPINFO_ENABLED [true]: " JMX_APPINFO_ENABLED
JMX_APPINFO_ENABLED=${JMX_APPINFO_ENABLED:-true}
read -r -p "Enter value for SPRING_DATASOURCE_URL (or press Enter to skip): " SPRING_DATASOURCE_URL
read -r -p "Enter value for SPRING_DATASOURCE_USERNAME (or press Enter to skip): " SPRING_DATASOURCE_USERNAME
read -r -s -p "Enter value for SPRING_DATASOURCE_PASSWORD (or press Enter to skip): " SPRING_DATASOURCE_PASSWORD
echo

# Escape characters special to sed replacement (\, |, &)
esc() { printf '%s' "$1" | sed -e 's/[\\|&]/\\&/g'; }

# Work on a temp copy so the template manifests keep their placeholders
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp kubernetes/*.yaml "$WORK_DIR/"

sed -i "s|{{IMAGE_URI}}|$(esc "$IMAGE_URI")|g" "$WORK_DIR/deployment.yaml"
sed -i "s|{{NAMESPACE}}|$NAMESPACE|g" "$WORK_DIR"/*.yaml
sed -i "s|{{WEATHER_API_KEY}}|$(esc "$WEATHER_API_KEY")|g" "$WORK_DIR/deployment.yaml"
sed -i "s|{{JMX_APPINFO_ENABLED}}|$(esc "$JMX_APPINFO_ENABLED")|g" "$WORK_DIR/deployment.yaml"
sed -i "s|{{SPRING_DATASOURCE_URL}}|$(esc "$SPRING_DATASOURCE_URL")|g" "$WORK_DIR/deployment.yaml"
sed -i "s|{{SPRING_DATASOURCE_USERNAME}}|$(esc "$SPRING_DATASOURCE_USERNAME")|g" "$WORK_DIR/deployment.yaml"
sed -i "s|{{SPRING_DATASOURCE_PASSWORD}}|$(esc "$SPRING_DATASOURCE_PASSWORD")|g" "$WORK_DIR/deployment.yaml"

echo "Configuring kubectl for AKS cluster ${CLUSTER_NAME}..."
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "Cannot connect to cluster"; exit 1; }

echo "Applying manifests..."
kubectl apply -f "$WORK_DIR/namespace.yaml"
kubectl apply -f "$WORK_DIR/deployment.yaml"
kubectl apply -f "$WORK_DIR/service.yaml"
kubectl apply -f "$WORK_DIR/ingress.yaml"

echo "Waiting for rollout..."
if ! kubectl rollout status deployment/${APP_NAME} -n ${NAMESPACE} --timeout=300s; then
  echo "Rollout failed. To roll back run:"
  echo "  kubectl rollout undo deployment/${APP_NAME} -n ${NAMESPACE}"
  exit 1
fi

kubectl get pods,svc,ingress -n ${NAMESPACE}

INGRESS_IP=$(kubectl get ingress ${APP_NAME}-ingress -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [ -n "$INGRESS_IP" ]; then
  echo "Application URL: http://${INGRESS_IP}/ (host: modresorts.example.com)"
else
  echo "Ingress IP not yet assigned. Check with: kubectl get ingress -n ${NAMESPACE}"
  echo "Or test via: kubectl port-forward svc/${APP_NAME}-service 8080:80 -n ${NAMESPACE}"
fi

echo "=== Deployment complete ==="
echo "Rollback: kubectl rollout undo deployment/${APP_NAME} -n ${NAMESPACE}"
