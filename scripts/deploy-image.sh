#!/bin/bash
set -e
set -o pipefail

APP_NAME="modresorts"
NAMESPACE="modresorts"

echo "=== Deploy ${APP_NAME} to AWS EKS ==="

for tool in aws kubectl; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool is required but not installed"; exit 1; }
done

read -r -p "AWS region (e.g. us-east-1): " AWS_REGION
read -r -p "EKS cluster name: " CLUSTER_NAME
read -r -p "Docker image URI (registry/repo:tag): " IMAGE_URI
[ -z "$AWS_REGION" ] && { echo "ERROR: AWS region is required"; exit 1; }
[ -z "$CLUSTER_NAME" ] && { echo "ERROR: cluster name is required"; exit 1; }
[ -z "$IMAGE_URI" ] && { echo "ERROR: image URI is required"; exit 1; }

read -r -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
read -r -p "Enter value for SERVER_NAME (or press Enter to skip): " SERVER_NAME

# Work on a temporary copy so the template manifests stay untouched
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp -r kubernetes/. "$WORK_DIR/"

sed -i.bak "s|{{IMAGE_URI}}|${IMAGE_URI}|g" "$WORK_DIR/deployment.yaml"
sed -i.bak "s|{{NAMESPACE}}|${NAMESPACE}|g" "$WORK_DIR"/*.yaml
sed -i.bak "s|{{WEATHER_API_KEY}}|${WEATHER_API_KEY}|g" "$WORK_DIR/deployment.yaml"
sed -i.bak "s|{{SERVER_NAME}}|${SERVER_NAME}|g" "$WORK_DIR/deployment.yaml"
rm -f "$WORK_DIR"/*.bak

echo "Configuring kubectl..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "ERROR: cannot reach cluster"; exit 1; }

echo "Applying manifests..."
kubectl apply -f "$WORK_DIR/namespace.yaml"
kubectl apply -f "$WORK_DIR/deployment.yaml"
kubectl apply -f "$WORK_DIR/service.yaml"
kubectl apply -f "$WORK_DIR/ingress.yaml"

echo "Waiting for rollout..."
if ! kubectl rollout status deployment/${APP_NAME} -n ${NAMESPACE} --timeout=300s; then
  echo "ERROR: rollout failed. To roll back run:"
  echo "  kubectl rollout undo deployment/${APP_NAME} -n ${NAMESPACE}"
  echo "Inspect with: kubectl describe pods -n ${NAMESPACE}; kubectl logs -l app=${APP_NAME} -n ${NAMESPACE}"
  exit 1
fi

kubectl get pods,svc,ingress -n ${NAMESPACE}

INGRESS_HOST=$(kubectl get ingress ${APP_NAME}-ingress -n ${NAMESPACE} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
if [ -n "$INGRESS_HOST" ]; then
  echo "Application URL: http://${INGRESS_HOST}/"
else
  echo "Ingress address not yet assigned. Check later with: kubectl get ingress -n ${NAMESPACE}"
fi
