#!/bin/bash
set -e
set -o pipefail

# Run from the repository root:  ./scripts/deploy-image.sh
APP_NAME="modresorts"
NAMESPACE="modresorts"
RENDER_DIR=".k8s-rendered"

echo "=== Deploy ${APP_NAME} to AWS EKS ==="

for tool in aws kubectl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool is not installed"; exit 1; }
done

read -r -p "AWS region (e.g. us-east-1): " AWS_REGION
read -r -p "EKS cluster name: " CLUSTER_NAME
read -r -p "Docker image URI (registry/repo:tag): " IMAGE_URI
if [ -z "$AWS_REGION" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$IMAGE_URI" ]; then
  echo "ERROR: region, cluster name and image URI are required"; exit 1
fi

read -r -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
read -r -p "Enter value for ENABLE_JMX_APPINFO [false]: " ENABLE_JMX_APPINFO
ENABLE_JMX_APPINFO=${ENABLE_JMX_APPINFO:-false}
read -r -p "Ingress host name [modresorts.example.com]: " INGRESS_HOST
INGRESS_HOST=${INGRESS_HOST:-modresorts.example.com}

esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

render() {
  sed -e "s|{{IMAGE_URI}}|$(esc "$IMAGE_URI")|g" \
      -e "s|{{NAMESPACE}}|$(esc "$NAMESPACE")|g" \
      -e "s|{{WEATHER_API_KEY}}|$(esc "$WEATHER_API_KEY")|g" \
      -e "s|{{ENABLE_JMX_APPINFO}}|$(esc "$ENABLE_JMX_APPINFO")|g" \
      -e "s|{{INGRESS_HOST}}|$(esc "$INGRESS_HOST")|g" \
      "$1" > "$2"
}

echo "Rendering manifests into ${RENDER_DIR}/ ..."
rm -rf "$RENDER_DIR"
mkdir -p "$RENDER_DIR"
for f in namespace deployment service ingress; do
  render "kubernetes/${f}.yaml" "${RENDER_DIR}/${f}.yaml"
done

echo "Configuring kubectl..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" || { echo "ERROR: failed to update kubeconfig"; exit 1; }

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "ERROR: cannot reach cluster"; exit 1; }

echo "Applying manifests..."
kubectl apply -f "${RENDER_DIR}/namespace.yaml"
kubectl apply -f "${RENDER_DIR}/deployment.yaml"
kubectl apply -f "${RENDER_DIR}/service.yaml"
kubectl apply -f "${RENDER_DIR}/ingress.yaml"

echo "Waiting for rollout..."
if ! kubectl rollout status "deployment/${APP_NAME}" -n "$NAMESPACE" --timeout=300s; then
  echo "ERROR: rollout failed. To roll back run:"
  echo "  kubectl rollout undo deployment/${APP_NAME} -n ${NAMESPACE}"
  echo "Inspect with: kubectl describe pods -n ${NAMESPACE}; kubectl logs -l app=${APP_NAME} -n ${NAMESPACE}"
  exit 1
fi

kubectl get pods,svc,ingress -n "$NAMESPACE"

ALB_HOST=$(kubectl get ingress "${APP_NAME}-ingress" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
if [ -n "$ALB_HOST" ]; then
  echo "Application URL: http://${ALB_HOST}/  (Host header: ${INGRESS_HOST})"
else
  echo "Ingress address not yet assigned. Check later with: kubectl get ingress -n ${NAMESPACE}"
fi
echo "Rollback if needed: kubectl rollout undo deployment/${APP_NAME} -n ${NAMESPACE}"
