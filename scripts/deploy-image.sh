#!/bin/bash
set -e
set -o pipefail

APP_NAME="modresorts"
NAMESPACE="modresorts"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

echo "=== Deploy $APP_NAME to AWS EKS ==="
read -p "Enter AWS region (e.g. us-east-1): " AWS_REGION
read -p "Enter EKS cluster name: " CLUSTER_NAME
read -p "Enter Docker image URI (registry/repo:tag): " IMAGE_URI
if [ -z "$AWS_REGION" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$IMAGE_URI" ]; then
  echo "AWS region, cluster name and image URI are required"
  exit 1
fi

read -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
read -p "Enter value for ENABLE_JMX_MBEAN [true]: " ENABLE_JMX_MBEAN
ENABLE_JMX_MBEAN=${ENABLE_JMX_MBEAN:-true}

# Work on a copy of the manifests so templates remain unchanged
cp kubernetes/*.yaml "$WORK_DIR/"
sed -i.bak "s|{{IMAGE_URI}}|$IMAGE_URI|g" "$WORK_DIR/deployment.yaml"
sed -i.bak "s|{{NAMESPACE}}|$NAMESPACE|g" "$WORK_DIR"/*.yaml
sed -i.bak "s|{{WEATHER_API_KEY}}|$WEATHER_API_KEY|g" "$WORK_DIR/deployment.yaml"
sed -i.bak "s|{{ENABLE_JMX_MBEAN}}|$ENABLE_JMX_MBEAN|g" "$WORK_DIR/deployment.yaml"

echo "Configuring kubectl..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "Verifying cluster connectivity..."
kubectl cluster-info || exit 1

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
  echo "Application URL: http://$INGRESS_HOST"
else
  echo "Ingress address not yet assigned. Check: kubectl get ingress -n $NAMESPACE"
fi
echo "Rollback if needed: kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
