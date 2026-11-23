#!/bin/bash
set -e
set -o pipefail

APP_NAME="modresorts"
NAMESPACE="modresorts"
MANIFEST_SRC="kubernetes"

echo "=== Deploy $APP_NAME to AWS EKS ==="

for cmd in aws kubectl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd is required but not installed"; exit 1; }
done

if [ ! -d "$MANIFEST_SRC" ]; then
  echo "ERROR: run this script from the project root (kubernetes/ directory not found)"; exit 1
fi

read -r -p "Enter AWS region (e.g. us-east-1): " AWS_REGION
read -r -p "Enter EKS cluster name: " CLUSTER_NAME
read -r -p "Enter Docker image URI (registry/repo:tag): " IMAGE_URI

if [ -z "$AWS_REGION" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$IMAGE_URI" ]; then
  echo "ERROR: AWS region, cluster name and image URI are required"; exit 1
fi

echo "Optional application settings (press Enter to skip)"
read -r -p "Enter value for WEATHER_SERVICE_URL (or press Enter to skip): " WEATHER_SERVICE_URL
read -r -s -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
echo ""
read -r -p "Enter value for JNDI_INITIAL_CONTEXT_FACTORY (or press Enter to skip): " JNDI_INITIAL_CONTEXT_FACTORY
read -r -p "Enter value for JNDI_PROVIDER_URL (or press Enter to skip): " JNDI_PROVIDER_URL

# Escape characters special to sed replacement text (\ & |)
esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp "$MANIFEST_SRC"/*.yaml "$WORK_DIR"/

sed -i.bak \
  -e "s|{{IMAGE_URI}}|$(esc "$IMAGE_URI")|g" \
  -e "s|{{NAMESPACE}}|$NAMESPACE|g" \
  -e "s|{{WEATHER_SERVICE_URL}}|$(esc "$WEATHER_SERVICE_URL")|g" \
  -e "s|{{WEATHER_API_KEY}}|$(esc "$WEATHER_API_KEY")|g" \
  -e "s|{{JNDI_INITIAL_CONTEXT_FACTORY}}|$(esc "$JNDI_INITIAL_CONTEXT_FACTORY")|g" \
  -e "s|{{JNDI_PROVIDER_URL}}|$(esc "$JNDI_PROVIDER_URL")|g" \
  "$WORK_DIR"/*.yaml
rm -f "$WORK_DIR"/*.bak

echo "Configuring kubectl for cluster $CLUSTER_NAME..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "ERROR: cannot reach cluster"; exit 1; }

echo "Applying manifests..."
kubectl apply -f "$WORK_DIR/namespace.yaml"
kubectl apply -f "$WORK_DIR/deployment.yaml"
kubectl apply -f "$WORK_DIR/service.yaml"
kubectl apply -f "$WORK_DIR/ingress.yaml"

echo "Waiting for rollout..."
if ! kubectl rollout status deployment/"$APP_NAME" -n "$NAMESPACE" --timeout=300s; then
  echo "ERROR: rollout failed."
  echo "Rollback with: kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
  echo "Inspect with:  kubectl describe pods -n $NAMESPACE ; kubectl logs deployment/$APP_NAME -n $NAMESPACE"
  exit 1
fi

kubectl get pods,svc,ingress -n "$NAMESPACE"

ALB_HOST=""
for i in 1 2 3 4 5 6 7 8 9 10; do
  ALB_HOST=$(kubectl get ingress modresorts-ingress -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -n "$ALB_HOST" ] && break
  sleep 15
done

if [ -n "$ALB_HOST" ]; then
  echo "Application URL: http://$ALB_HOST/"
else
  echo "Ingress address not yet assigned. Check: kubectl get ingress -n $NAMESPACE"
  echo "(Requires the AWS Load Balancer Controller installed in the cluster.)"
fi

echo "Rollback instructions: kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
