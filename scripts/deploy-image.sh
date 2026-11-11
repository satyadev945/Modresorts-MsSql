#!/bin/bash
set -e
set -o pipefail

APP_NAME="modresorts"
NAMESPACE="modresorts"

echo "=== Deploy $APP_NAME to AWS EKS ==="
read -r -p "AWS region (e.g. us-east-1): " AWS_REGION
read -r -p "EKS cluster name: " CLUSTER_NAME
read -r -p "Docker image URI (registry/repo:tag): " IMAGE_URI

if [ -z "$AWS_REGION" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$IMAGE_URI" ]; then
  echo "AWS region, cluster name and image URI are required"
  exit 1
fi

read -r -p "Enter value for REDIS_HOST (or press Enter to skip): " REDIS_HOST
read -r -p "Enter value for REDIS_PORT (or press Enter for 6379): " REDIS_PORT
REDIS_PORT=${REDIS_PORT:-6379}
read -r -s -p "Enter value for REDIS_PASSWORD (or press Enter to skip): " REDIS_PASSWORD
echo
read -r -s -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
echo

# Work on a temporary copy so the template manifests keep their placeholders
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp kubernetes/*.yaml "$WORK_DIR/"

sed -i.bak "s|{{IMAGE_URI}}|$IMAGE_URI|g" "$WORK_DIR/deployment.yaml"
sed -i.bak "s|{{NAMESPACE}}|$NAMESPACE|g" "$WORK_DIR"/*.yaml
sed -i.bak "s|{{REDIS_HOST}}|$REDIS_HOST|g" "$WORK_DIR/deployment.yaml"
sed -i.bak "s|{{REDIS_PORT}}|$REDIS_PORT|g" "$WORK_DIR/deployment.yaml"
sed -i.bak "s|{{REDIS_PASSWORD}}|$REDIS_PASSWORD|g" "$WORK_DIR/deployment.yaml"
sed -i.bak "s|{{WEATHER_API_KEY}}|$WEATHER_API_KEY|g" "$WORK_DIR/deployment.yaml"

echo "Configuring kubectl..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "Cannot reach the cluster"; exit 1; }

echo "Applying manifests..."
kubectl apply -f "$WORK_DIR/namespace.yaml"
kubectl apply -f "$WORK_DIR/deployment.yaml"
kubectl apply -f "$WORK_DIR/service.yaml"
kubectl apply -f "$WORK_DIR/ingress.yaml"

echo "Waiting for rollout..."
if ! kubectl rollout status deployment/$APP_NAME -n $NAMESPACE --timeout=300s; then
  echo "Rollout failed. To roll back run:"
  echo "  kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
  exit 1
fi

kubectl get pods,svc,ingress -n $NAMESPACE

INGRESS_HOST=$(kubectl get ingress ${APP_NAME}-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
if [ -n "$INGRESS_HOST" ]; then
  echo "Application URL: http://$INGRESS_HOST/"
else
  echo "Ingress address not yet assigned. Check with: kubectl get ingress -n $NAMESPACE"
fi
