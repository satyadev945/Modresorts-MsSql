#!/bin/bash
set -e
set -o pipefail

# Run from the repository root
APP_NAME="modresorts"
NAMESPACE="modresorts"

echo "=== Deploy ModResorts to AWS EKS ==="
read -r -p "Enter AWS region (e.g. us-east-1): " AWS_REGION
read -r -p "Enter EKS cluster name: " CLUSTER_NAME
read -r -p "Enter Docker image URI (registry/repo:tag): " IMAGE_URI
if [ -z "$AWS_REGION" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$IMAGE_URI" ]; then
  echo "ERROR: region, cluster name and image URI are required"; exit 1
fi

read -r -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
read -r -p "Enter value for SERVER_NAME (or press Enter to skip): " SERVER_NAME

# Work on a temp copy so the templates keep their placeholders
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp kubernetes/*.yaml "$WORK_DIR/"

sed -i.bak "s|{{IMAGE_URI}}|$IMAGE_URI|g" "$WORK_DIR/deployment.yaml"
sed -i.bak "s|{{NAMESPACE}}|$NAMESPACE|g" "$WORK_DIR"/*.yaml
sed -i.bak "s|{{WEATHER_API_KEY}}|$WEATHER_API_KEY|g" "$WORK_DIR/deployment.yaml"
sed -i.bak "s|{{SERVER_NAME}}|$SERVER_NAME|g" "$WORK_DIR/deployment.yaml"
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
  echo "ERROR: rollout failed."
  echo "Rollback with: kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
  echo "Inspect with:  kubectl describe pods -n $NAMESPACE ; kubectl logs -l app=$APP_NAME -n $NAMESPACE"
  exit 1
fi

kubectl get pods,svc,ingress -n $NAMESPACE

echo "Waiting for ingress address (may take a few minutes)..."
INGRESS_HOST=""
for i in $(seq 1 30); do
  INGRESS_HOST=$(kubectl get ingress ${APP_NAME}-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  [ -n "$INGRESS_HOST" ] && break
  sleep 10
done
if [ -n "$INGRESS_HOST" ]; then
  echo "Application URL: http://$INGRESS_HOST/"
else
  echo "Ingress address not yet assigned. Check: kubectl get ingress -n $NAMESPACE"
  echo "(Requires AWS Load Balancer Controller installed in the cluster.)"
fi
