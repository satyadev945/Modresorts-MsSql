#!/bin/bash
set -e
set -o pipefail

APP_NAME="testcomp1"
NAMESPACE="testcomp1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_SRC="${SCRIPT_DIR}/../kubernetes"

# Escape a value for use in a sed replacement using the | delimiter
esc() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

echo "=== Deploy ${APP_NAME} to AWS EKS ==="

for tool in aws kubectl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Error: $tool is not installed or not in PATH."
    exit 1
  fi
done

read -r -p "Enter AWS region (e.g. us-east-1): " AWS_REGION
read -r -p "Enter EKS cluster name: " CLUSTER_NAME
read -r -p "Enter Docker image URI (registry/repo:tag): " IMAGE_URI

if [ -z "$AWS_REGION" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$IMAGE_URI" ]; then
  echo "Error: AWS region, cluster name and image URI are required."
  exit 1
fi

echo "Enter application environment variables (press Enter to skip)"
read -r -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
read -r -p "Enter value for SERVER_NAME (or press Enter to skip): " SERVER_NAME
read -r -p "Enter value for JNDI_INITIAL_CONTEXT_FACTORY (or press Enter for default): " JNDI_INITIAL_CONTEXT_FACTORY
read -r -p "Enter value for JNDI_PROVIDER_URL (or press Enter to skip): " JNDI_PROVIDER_URL
JNDI_INITIAL_CONTEXT_FACTORY=${JNDI_INITIAL_CONTEXT_FACTORY:-org.apache.naming.java.javaURLContextFactory}
SERVER_NAME=${SERVER_NAME:-localhost}

# Work on a temporary copy so the template manifests keep their placeholders
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp -r "$K8S_SRC"/. "$WORK_DIR"/

for f in "$WORK_DIR"/*.yaml; do
  sed -i.bak \
    -e 's|{{IMAGE_URI}}|'"$(esc "$IMAGE_URI")"'|g' \
    -e 's|{{NAMESPACE}}|'"$(esc "$NAMESPACE")"'|g' \
    -e 's|{{WEATHER_API_KEY}}|'"$(esc "$WEATHER_API_KEY")"'|g' \
    -e 's|{{SERVER_NAME}}|'"$(esc "$SERVER_NAME")"'|g' \
    -e 's|{{JNDI_INITIAL_CONTEXT_FACTORY}}|'"$(esc "$JNDI_INITIAL_CONTEXT_FACTORY")"'|g' \
    -e 's|{{JNDI_PROVIDER_URL}}|'"$(esc "$JNDI_PROVIDER_URL")"'|g' \
    "$f"
  rm -f "$f.bak"
done

echo "Configuring kubectl for cluster ${CLUSTER_NAME}..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "Error: cannot reach the cluster."; exit 1; }

echo "Applying manifests..."
kubectl apply -f "$WORK_DIR/namespace.yaml"
kubectl apply -f "$WORK_DIR/deployment.yaml"
kubectl apply -f "$WORK_DIR/service.yaml"
kubectl apply -f "$WORK_DIR/ingress.yaml"

echo "Waiting for rollout..."
if ! kubectl rollout status deployment/${APP_NAME} -n ${NAMESPACE} --timeout=300s; then
  echo "Rollout failed. To roll back run:"
  echo "  kubectl rollout undo deployment/${APP_NAME} -n ${NAMESPACE}"
  echo "Inspect with: kubectl describe pods -n ${NAMESPACE} ; kubectl logs deployment/${APP_NAME} -n ${NAMESPACE}"
  exit 1
fi

echo "Resources:"
kubectl get pods,svc,ingress -n ${NAMESPACE}

INGRESS_HOST=$(kubectl get ingress ${APP_NAME}-ingress -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
if [ -n "$INGRESS_HOST" ]; then
  echo "Application URL: http://${INGRESS_HOST}/"
else
  echo "Ingress address not yet assigned. Check later with:"
  echo "  kubectl get ingress ${APP_NAME}-ingress -n ${NAMESPACE}"
fi
echo "Health endpoint: /health"
