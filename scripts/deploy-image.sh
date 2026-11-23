#!/bin/bash
# Deploy TestComp1 to AWS EKS. Run from the repository root.
set -e
set -o pipefail

APP_NAME="testcomp1"
NAMESPACE="testcomp1"
MANIFEST_DIR="kubernetes"

if [ ! -d "$MANIFEST_DIR" ]; then
  echo "ERROR: '$MANIFEST_DIR' directory not found. Run this script from the repository root." >&2
  exit 1
fi

for cmd in aws kubectl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd is not installed or not in PATH." >&2; exit 1; }
done

read -r -p "Enter AWS region (e.g. us-east-1): " AWS_REGION
read -r -p "Enter EKS cluster name: " CLUSTER_NAME
read -r -p "Enter Docker image URI (registry/repo:tag): " IMAGE_URI

if [ -z "$AWS_REGION" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$IMAGE_URI" ]; then
  echo "ERROR: AWS region, cluster name and image URI are required." >&2
  exit 1
fi

echo "Optional application settings (press Enter to skip)"
read -r -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
read -r -p "Enter value for WEATHER_SERVICE_URL (or press Enter to skip): " WEATHER_SERVICE_URL

# Render manifests into a temp directory so the templates stay untouched
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp "$MANIFEST_DIR"/*.yaml "$WORK_DIR"/

for f in "$WORK_DIR"/*.yaml; do
  sed -e 's|{{IMAGE_URI}}|'"$IMAGE_URI"'|g' \
      -e 's|{{NAMESPACE}}|'"$NAMESPACE"'|g' \
      -e 's|{{WEATHER_API_KEY}}|'"$WEATHER_API_KEY"'|g' \
      -e 's|{{WEATHER_SERVICE_URL}}|'"$WEATHER_SERVICE_URL"'|g' \
      "$f" > "$f.rendered"
  mv "$f.rendered" "$f"
done

echo "Configuring kubectl for cluster $CLUSTER_NAME..."
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "ERROR: cannot reach the cluster." >&2; exit 1; }

echo "Applying manifests..."
kubectl apply -f "$WORK_DIR/namespace.yaml"
kubectl apply -f "$WORK_DIR/deployment.yaml"
kubectl apply -f "$WORK_DIR/service.yaml"
kubectl apply -f "$WORK_DIR/ingress.yaml"

echo "Waiting for rollout..."
if ! kubectl rollout status deployment/"$APP_NAME" -n "$NAMESPACE" --timeout=300s; then
  echo "ERROR: Rollout failed. To roll back run:" >&2
  echo "  kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE" >&2
  exit 1
fi

kubectl get pods,svc,ingress -n "$NAMESPACE"

INGRESS_HOST=$(kubectl get ingress "${APP_NAME}-ingress" -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
if [ -n "$INGRESS_HOST" ]; then
  echo "Application URL: http://$INGRESS_HOST (Host header: testcomp1.example.com unless you changed ingress.yaml)"
else
  echo "Ingress address not yet assigned. Check later with: kubectl get ingress -n $NAMESPACE"
fi

echo "Rollback instructions: kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
