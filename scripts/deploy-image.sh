#!/bin/bash
# Deploy ModResorts to AWS EKS. Run from the repository root.
set -e
set -o pipefail

APP_NAME="modresorts"
NAMESPACE="modresorts"

echo "=== ModResorts deployment to AWS EKS ==="
read -r -p "Enter AWS region (e.g. us-east-1): " AWS_REGION
read -r -p "Enter EKS cluster name: " CLUSTER_NAME
read -r -p "Enter Docker image URI (registry/repo:tag): " IMAGE_URI
if [ -z "$AWS_REGION" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$IMAGE_URI" ]; then
  echo "AWS region, cluster name and image URI are required"; exit 1
fi

read -r -p "Enter value for WEATHER_SERVICE_URL (or press Enter to skip): " WEATHER_SERVICE_URL
read -r -s -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
echo

command -v aws >/dev/null 2>&1 || { echo "aws cli is required"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "kubectl is required"; exit 1; }

# Work on a temporary copy so the templates keep their placeholders
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp kubernetes/*.yaml "$WORK_DIR"/

sed -i 's|{{IMAGE_URI}}|'"$IMAGE_URI"'|g' "$WORK_DIR/deployment.yaml"
sed -i 's|{{NAMESPACE}}|'"$NAMESPACE"'|g' "$WORK_DIR"/*.yaml
sed -i 's|{{WEATHER_SERVICE_URL}}|'"$WEATHER_SERVICE_URL"'|g' "$WORK_DIR/deployment.yaml"
sed -i 's|{{WEATHER_API_KEY}}|'"$WEATHER_API_KEY"'|g' "$WORK_DIR/deployment.yaml"

echo "Configuring kubectl..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "Cannot reach cluster"; exit 1; }

echo "Applying manifests..."
kubectl apply -f "$WORK_DIR/namespace.yaml"
kubectl apply -f "$WORK_DIR/deployment.yaml"
kubectl apply -f "$WORK_DIR/service.yaml"
kubectl apply -f "$WORK_DIR/ingress.yaml"

echo "Waiting for rollout..."
if ! kubectl rollout status deployment/$APP_NAME -n $NAMESPACE --timeout=300s; then
  echo "Rollout failed. To roll back run:"
  echo "  kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
  echo "Inspect with: kubectl describe pods -n $NAMESPACE ; kubectl logs -l app=$APP_NAME -n $NAMESPACE"
  exit 1
fi

kubectl get pods,svc,ingress -n $NAMESPACE

INGRESS_HOST=$(kubectl get ingress ${APP_NAME}-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
if [ -n "$INGRESS_HOST" ]; then
  echo "Application URL: http://$INGRESS_HOST (send Host header modresorts.example.com or edit the ingress host)"
else
  echo "Ingress address not yet assigned. Check: kubectl get ingress -n $NAMESPACE"
fi
echo "Rollback if needed: kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
