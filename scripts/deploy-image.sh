#!/bin/bash
set -e
set -o pipefail

APP_NAME="modresorts"
NAMESPACE="modresorts"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_K8S_DIR="$SCRIPT_DIR/../kubernetes"

read -r -p "AWS region [us-east-1]: " AWS_REGION
AWS_REGION=${AWS_REGION:-us-east-1}
read -r -p "EKS cluster name: " CLUSTER_NAME
[ -n "$CLUSTER_NAME" ] || { echo "EKS cluster name is required"; exit 1; }
read -r -p "Docker image URI (registry/repo:tag): " IMAGE_URI
[ -n "$IMAGE_URI" ] || { echo "Image URI is required"; exit 1; }
read -r -p "Ingress host [modresorts.example.com]: " INGRESS_HOST
INGRESS_HOST=${INGRESS_HOST:-modresorts.example.com}

read -r -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
read -r -p "Enter value for WEATHER_SERVICE_URL (or press Enter to skip): " WEATHER_SERVICE_URL
read -r -p "Enter value for SERVER_DISPLAY_NAME (or press Enter to skip): " SERVER_DISPLAY_NAME
read -r -p "Enter value for JNDI_INITIAL_CONTEXT_FACTORY (or press Enter to skip): " JNDI_INITIAL_CONTEXT_FACTORY
read -r -p "Enter value for JNDI_PROVIDER_URL (or press Enter to skip): " JNDI_PROVIDER_URL

# Work on a copy so the template manifests stay untouched
K8S_DIR=$(mktemp -d)
trap 'rm -rf "$K8S_DIR"' EXIT
cp "$SRC_K8S_DIR"/*.yaml "$K8S_DIR"/

# Escape characters special to sed replacement (\ & |)
esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

replace() {
  local key="$1" value
  value=$(esc "$2")
  sed -i 's|{{'"$key"'}}|'"$value"'|g' "$K8S_DIR"/*.yaml
}

replace IMAGE_URI "$IMAGE_URI"
replace NAMESPACE "$NAMESPACE"
replace INGRESS_HOST "$INGRESS_HOST"
replace WEATHER_API_KEY "$WEATHER_API_KEY"
replace WEATHER_SERVICE_URL "$WEATHER_SERVICE_URL"
replace SERVER_DISPLAY_NAME "$SERVER_DISPLAY_NAME"
replace JNDI_INITIAL_CONTEXT_FACTORY "$JNDI_INITIAL_CONTEXT_FACTORY"
replace JNDI_PROVIDER_URL "$JNDI_PROVIDER_URL"

echo "Configuring kubectl for cluster $CLUSTER_NAME ..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "Verifying cluster connectivity ..."
kubectl cluster-info || { echo "Cannot reach the cluster"; exit 1; }

echo "Applying manifests ..."
kubectl apply -f "$K8S_DIR/namespace.yaml"
kubectl apply -f "$K8S_DIR/deployment.yaml"
kubectl apply -f "$K8S_DIR/service.yaml"
kubectl apply -f "$K8S_DIR/ingress.yaml"

echo "Waiting for rollout ..."
if ! kubectl rollout status deployment/$APP_NAME -n $NAMESPACE --timeout=300s; then
  echo "Rollout failed. To roll back run:"
  echo "  kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
  exit 1
fi

kubectl get pods,svc,ingress -n $NAMESPACE

ALB_HOST=$(kubectl get ingress ${APP_NAME}-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
if [ -n "$ALB_HOST" ]; then
  echo "Application URL: http://$ALB_HOST (Host header: $INGRESS_HOST)"
else
  echo "Ingress address not yet assigned. Check later: kubectl get ingress -n $NAMESPACE"
fi
