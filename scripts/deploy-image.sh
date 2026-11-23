#!/bin/bash
# Deploy TestComp1 to AWS EKS. Run from the repository root:  ./scripts/deploy-image.sh
set -e
set -o pipefail

APP_NAME="testcomp1"
NAMESPACE="testcomp1"

if [ ! -d "kubernetes" ]; then
  echo "ERROR: kubernetes/ directory not found. Run this script from the repository root."
  exit 1
fi

command -v aws >/dev/null 2>&1 || { echo "ERROR: aws CLI is required."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl is required."; exit 1; }

echo "=== TestComp1 - Deploy to AWS EKS ==="

read -r -p "AWS region (e.g. us-east-1): " AWS_REGION
read -r -p "EKS cluster name: " CLUSTER_NAME
read -r -p "Docker image URI (registry/repo:tag): " IMAGE_URI
if [ -z "$AWS_REGION" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$IMAGE_URI" ]; then
  echo "ERROR: AWS region, cluster name and image URI are required."
  exit 1
fi

echo "--- Application configuration (press Enter to skip) ---"
read -r -p "Enter value for REDIS_HOST (or press Enter to skip): " REDIS_HOST
read -r -p "Enter value for REDIS_PORT (or press Enter for 6379): " REDIS_PORT
REDIS_PORT=${REDIS_PORT:-6379}
read -r -p "Enter value for SERVER_DISPLAY_NAME (or press Enter for $APP_NAME): " SERVER_DISPLAY_NAME
SERVER_DISPLAY_NAME=${SERVER_DISPLAY_NAME:-$APP_NAME}
read -r -s -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
echo
read -r -p "Enter ingress host (or press Enter for $APP_NAME.example.com): " INGRESS_HOST
INGRESS_HOST=${INGRESS_HOST:-$APP_NAME.example.com}

# Work on a temporary copy so repository manifests keep their placeholders
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp -R kubernetes "$WORK_DIR/kubernetes"

sed -i.bak "s|{{IMAGE_URI}}|$IMAGE_URI|g" "$WORK_DIR/kubernetes/deployment.yaml"
sed -i.bak "s|{{REDIS_HOST}}|$REDIS_HOST|g" "$WORK_DIR/kubernetes/deployment.yaml"
sed -i.bak "s|{{REDIS_PORT}}|$REDIS_PORT|g" "$WORK_DIR/kubernetes/deployment.yaml"
sed -i.bak "s|{{SERVER_DISPLAY_NAME}}|$SERVER_DISPLAY_NAME|g" "$WORK_DIR/kubernetes/deployment.yaml"
sed -i.bak "s|{{INGRESS_HOST}}|$INGRESS_HOST|g" "$WORK_DIR/kubernetes/ingress.yaml"
sed -i.bak "s|{{NAMESPACE}}|$NAMESPACE|g" "$WORK_DIR"/kubernetes/*.yaml

echo "Configuring kubectl for cluster $CLUSTER_NAME..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "ERROR: cannot reach the cluster."; exit 1; }

echo "Applying manifests..."
kubectl apply -f "$WORK_DIR/kubernetes/namespace.yaml"

if [ -n "$WEATHER_API_KEY" ]; then
  kubectl create secret generic testcomp1-weather-secret \
    --namespace "$NAMESPACE" \
    --from-literal=WEATHER_API_KEY="$WEATHER_API_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

kubectl apply -f "$WORK_DIR/kubernetes/deployment.yaml"
kubectl apply -f "$WORK_DIR/kubernetes/service.yaml"
kubectl apply -f "$WORK_DIR/kubernetes/ingress.yaml"

echo "Waiting for rollout..."
if ! kubectl rollout status deployment/$APP_NAME -n "$NAMESPACE" --timeout=300s; then
  echo "ERROR: rollout failed."
  echo "Inspect:  kubectl describe pods -n $NAMESPACE ; kubectl logs deployment/$APP_NAME -n $NAMESPACE"
  echo "Rollback: kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
  exit 1
fi

kubectl get pods,svc,ingress -n "$NAMESPACE"

echo "Waiting for load balancer address (up to ~2 min)..."
ALB_HOST=""
for i in $(seq 1 12); do
  ALB_HOST=$(kubectl get ingress ${APP_NAME}-ingress -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -n "$ALB_HOST" ] && break
  sleep 10
done

if [ -n "$ALB_HOST" ]; then
  echo "Application URL: http://$ALB_HOST/  (host header: $INGRESS_HOST)"
  echo "Health check:    http://$ALB_HOST/health"
else
  echo "Load balancer address not yet assigned. Check: kubectl get ingress -n $NAMESPACE"
fi

echo "Rollback if needed: kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
