#!/bin/bash
# Deploy ModResorts to GKE. Run from the repository root: ./scripts/deploy-image.sh
set -e
set -o pipefail

APP_NAME="modresorts"

echo "=== ModResorts GKE deployment ==="
read -r -p "Enter GCP project ID: " GCP_PROJECT
read -r -p "Enter GKE cluster zone or region (e.g. us-central1-a): " GCP_ZONE
read -r -p "Enter GKE cluster name: " CLUSTER_NAME
read -r -p "Enter full Docker image URI (registry/path:tag): " IMAGE_URI
read -r -p "Enter Kubernetes namespace [${APP_NAME}]: " NAMESPACE
NAMESPACE=${NAMESPACE:-$APP_NAME}
read -r -p "Enter ingress host [modresorts.example.com]: " INGRESS_HOST
INGRESS_HOST=${INGRESS_HOST:-modresorts.example.com}

for v in GCP_PROJECT GCP_ZONE CLUSTER_NAME IMAGE_URI; do
  if [ -z "${!v}" ]; then echo "ERROR: $v is required"; exit 1; fi
done

echo "Optional application settings (press Enter to skip)"
read -r -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
read -r -p "Enter value for JNDI_INITIAL_CONTEXT_FACTORY (or press Enter to skip): " JNDI_INITIAL_CONTEXT_FACTORY
read -r -p "Enter value for JNDI_PROVIDER_URL (or press Enter to skip): " JNDI_PROVIDER_URL
read -r -p "Enter value for SERVER_DISPLAY_NAME (or press Enter to skip): " SERVER_DISPLAY_NAME

# Escape characters that are special on the sed replacement side (\, &, |)
esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

RENDER_DIR=$(mktemp -d)
trap 'rm -rf "$RENDER_DIR"' EXIT
cp kubernetes/*.yaml "$RENDER_DIR/"

for f in "$RENDER_DIR"/*.yaml; do
  sed -e "s|{{IMAGE_URI}}|$(esc "$IMAGE_URI")|g" \
      -e "s|{{NAMESPACE}}|$(esc "$NAMESPACE")|g" \
      -e "s|{{INGRESS_HOST}}|$(esc "$INGRESS_HOST")|g" \
      -e "s|{{WEATHER_API_KEY}}|$(esc "$WEATHER_API_KEY")|g" \
      -e "s|{{JNDI_INITIAL_CONTEXT_FACTORY}}|$(esc "$JNDI_INITIAL_CONTEXT_FACTORY")|g" \
      -e "s|{{JNDI_PROVIDER_URL}}|$(esc "$JNDI_PROVIDER_URL")|g" \
      -e "s|{{SERVER_DISPLAY_NAME}}|$(esc "$SERVER_DISPLAY_NAME")|g" \
      "$f" > "$f.tmp"
  mv "$f.tmp" "$f"
done

echo "Configuring kubectl..."
gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$GCP_ZONE" --project "$GCP_PROJECT"
kubectl cluster-info || { echo "ERROR: cannot reach cluster"; exit 1; }

echo "Applying manifests..."
kubectl apply -f "$RENDER_DIR/namespace.yaml"
kubectl apply -f "$RENDER_DIR/deployment.yaml"
kubectl apply -f "$RENDER_DIR/service.yaml"
kubectl apply -f "$RENDER_DIR/ingress.yaml"

echo "Waiting for rollout..."
if ! kubectl rollout status deployment/${APP_NAME} -n "$NAMESPACE" --timeout=300s; then
  echo "ERROR: rollout failed. To roll back run:"
  echo "  kubectl rollout undo deployment/${APP_NAME} -n $NAMESPACE"
  echo "Diagnose with: kubectl describe pods -n $NAMESPACE ; kubectl logs deployment/${APP_NAME} -n $NAMESPACE"
  exit 1
fi

kubectl get pods,svc,ingress -n "$NAMESPACE"

INGRESS_IP=$(kubectl get ingress ${APP_NAME}-ingress -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
if [ -n "$INGRESS_IP" ]; then
  echo "Application URL: http://${INGRESS_IP}/  (Host header: ${INGRESS_HOST})"
else
  echo "Ingress IP not yet assigned. Check later with: kubectl get ingress -n $NAMESPACE"
fi
echo "Rollback if needed: kubectl rollout undo deployment/${APP_NAME} -n $NAMESPACE"
