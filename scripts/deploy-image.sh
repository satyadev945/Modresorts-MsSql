#!/bin/bash
set -e
set -o pipefail

APP_NAME="modresorts"
NAMESPACE="modresorts"

echo "=== ModResorts - Deploy to AWS EKS ==="

read -r -p "Enter AWS region (e.g. us-east-1): " AWS_REGION
read -r -p "Enter EKS cluster name: " CLUSTER_NAME
read -r -p "Enter Docker image URI (registry/repo:tag): " IMAGE_URI
if [ -z "$AWS_REGION" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$IMAGE_URI" ]; then
  echo "ERROR: AWS region, cluster name and image URI are required"; exit 1
fi

read -r -p "Enter value for REDIS_HOST (or press Enter to skip) [redis]: " REDIS_HOST
read -r -p "Enter value for REDIS_PORT (or press Enter to skip) [6379]: " REDIS_PORT
read -r -p "Enter value for REDIS_CACHE_TTL (or press Enter to skip) [300]: " REDIS_CACHE_TTL
read -r -s -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
echo
read -r -p "Enter ingress host name [modresorts.example.com]: " INGRESS_HOST
REDIS_HOST=${REDIS_HOST:-redis}
REDIS_PORT=${REDIS_PORT:-6379}
REDIS_CACHE_TTL=${REDIS_CACHE_TTL:-300}
INGRESS_HOST=${INGRESS_HOST:-modresorts.example.com}

# Work on a temporary copy so the template manifests stay untouched
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp -r kubernetes/. "$WORK_DIR/"

sed -i.bak "s|{{IMAGE_URI}}|$IMAGE_URI|g" "$WORK_DIR/deployment.yaml"
sed -i.bak "s|{{REDIS_HOST}}|$REDIS_HOST|g" "$WORK_DIR/deployment.yaml"
sed -i.bak "s|{{REDIS_PORT}}|$REDIS_PORT|g" "$WORK_DIR/deployment.yaml"
sed -i.bak "s|{{REDIS_CACHE_TTL}}|$REDIS_CACHE_TTL|g" "$WORK_DIR/deployment.yaml"
sed -i.bak "s|{{WEATHER_API_KEY}}|$WEATHER_API_KEY|g" "$WORK_DIR/deployment.yaml"
sed -i.bak "s|modresorts.example.com|$INGRESS_HOST|g" "$WORK_DIR/ingress.yaml"
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
if ! kubectl rollout status deployment/$APP_NAME -n $NAMESPACE --timeout=300s; then
  echo "ERROR: Rollout failed. To roll back run:"
  echo "  kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
  echo "Inspect with: kubectl describe pods -n $NAMESPACE ; kubectl logs -l app=$APP_NAME -n $NAMESPACE"
  exit 1
fi

kubectl get pods,svc,ingress -n $NAMESPACE

ALB_HOST=$(kubectl get ingress ${APP_NAME}-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
if [ -n "$ALB_HOST" ]; then
  echo "Application URL: http://$ALB_HOST (Host header: $INGRESS_HOST)"
else
  echo "Ingress address not yet assigned. Check later: kubectl get ingress -n $NAMESPACE"
fi
echo "Rollback if needed: kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
