#!/bin/bash
# Deploy ModResorts to Azure AKS. Run from the repository root: ./scripts/deploy-image.sh
set -e
set -o pipefail

APP_NAME="modresorts"
NAMESPACE="modresorts"

for tool in az kubectl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool is not installed"; exit 1; }
done

read -r -p "Enter Azure resource group: " RESOURCE_GROUP
[ -n "$RESOURCE_GROUP" ] || { echo "ERROR: resource group is required"; exit 1; }
read -r -p "Enter AKS cluster name: " CLUSTER_NAME
[ -n "$CLUSTER_NAME" ] || { echo "ERROR: cluster name is required"; exit 1; }
read -r -p "Enter Docker image URI (e.g. myacr.azurecr.io/modresorts:latest): " IMAGE_URI
[ -n "$IMAGE_URI" ] || { echo "ERROR: image URI is required"; exit 1; }
read -r -p "Enter ingress host [modresorts.example.com]: " INGRESS_HOST
INGRESS_HOST=${INGRESS_HOST:-modresorts.example.com}

read -r -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
read -r -p "Enter value for WEATHER_API_KEY_FILE (or press Enter to skip): " WEATHER_API_KEY_FILE
read -r -p "Enter value for JNDI_INITIAL_CONTEXT_FACTORY (or press Enter to skip): " JNDI_INITIAL_CONTEXT_FACTORY
read -r -p "Enter value for JNDI_PROVIDER_URL (or press Enter to skip): " JNDI_PROVIDER_URL

# Work on a temporary copy so the template manifests keep their placeholders
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp kubernetes/*.yaml "$WORK_DIR"/

echo ">>> Rendering manifests ..."
sed -i.bak \
  -e "s|{{IMAGE_URI}}|$IMAGE_URI|g" \
  -e "s|{{NAMESPACE}}|$NAMESPACE|g" \
  -e "s|{{INGRESS_HOST}}|$INGRESS_HOST|g" \
  -e "s|{{WEATHER_API_KEY_FILE}}|$WEATHER_API_KEY_FILE|g" \
  -e "s|{{WEATHER_API_KEY}}|$WEATHER_API_KEY|g" \
  -e "s|{{JNDI_INITIAL_CONTEXT_FACTORY}}|$JNDI_INITIAL_CONTEXT_FACTORY|g" \
  -e "s|{{JNDI_PROVIDER_URL}}|$JNDI_PROVIDER_URL|g" \
  "$WORK_DIR"/*.yaml
rm -f "$WORK_DIR"/*.bak

echo ">>> Configuring kubectl for $CLUSTER_NAME ..."
az aks get-credentials --resource-group "$RESOURCE_GROUP" --name "$CLUSTER_NAME" --overwrite-existing || { echo "ERROR: failed to get AKS credentials"; exit 1; }
kubectl cluster-info || { echo "ERROR: cannot reach the cluster"; exit 1; }

echo ">>> Applying manifests ..."
kubectl apply -f "$WORK_DIR/namespace.yaml"
kubectl apply -f "$WORK_DIR/deployment.yaml"
kubectl apply -f "$WORK_DIR/service.yaml"
kubectl apply -f "$WORK_DIR/ingress.yaml"

echo ">>> Waiting for rollout ..."
if ! kubectl rollout status deployment/$APP_NAME -n $NAMESPACE --timeout=300s; then
  echo "ERROR: rollout failed. To roll back run:"
  echo "  kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
  echo "Inspect with: kubectl describe pods -n $NAMESPACE ; kubectl logs -l app=$APP_NAME -n $NAMESPACE"
  exit 1
fi

kubectl get pods,svc,ingress -n $NAMESPACE

INGRESS_IP=$(kubectl get ingress modresorts-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
echo
echo "Deployment complete."
echo "Application URL: http://${INGRESS_HOST}/  (ingress IP: ${INGRESS_IP:-pending})"
echo "Rollback if needed: kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
