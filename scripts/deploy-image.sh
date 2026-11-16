#!/bin/bash
set -e
set -o pipefail

APP_NAME="modresorts"
NAMESPACE="modresorts"

echo "=== Deploy $APP_NAME to GCP GKE (run from repository root) ==="

read -p "GCP project ID: " GCP_PROJECT
read -p "GCP zone (or region) of the cluster (e.g. us-central1-a): " GCP_ZONE
read -p "GKE cluster name: " CLUSTER_NAME
read -p "Docker image URI (full path with tag): " IMAGE_URI

if [ -z "$GCP_PROJECT" ] || [ -z "$GCP_ZONE" ] || [ -z "$CLUSTER_NAME" ] || [ -z "$IMAGE_URI" ]; then
  echo "ERROR: all of project, zone, cluster and image URI are required"; exit 1
fi

read -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
read -p "Enter value for GRPC_SERVICE_TARGET (or press Enter to skip): " GRPC_SERVICE_TARGET
read -p "Enter value for SERVER_NAME (or press Enter to use $APP_NAME): " SERVER_NAME
SERVER_NAME=${SERVER_NAME:-$APP_NAME}

# Work on a temporary copy so the templates keep their placeholders
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
cp kubernetes/*.yaml "$WORK_DIR"/

sed -i.bak "s|{{IMAGE_URI}}|$IMAGE_URI|g" "$WORK_DIR/deployment.yaml"
sed -i.bak "s|{{NAMESPACE}}|$NAMESPACE|g" "$WORK_DIR"/*.yaml
sed -i.bak "s|{{WEATHER_API_KEY}}|$WEATHER_API_KEY|g" "$WORK_DIR/deployment.yaml"
sed -i.bak "s|{{GRPC_SERVICE_TARGET}}|$GRPC_SERVICE_TARGET|g" "$WORK_DIR/deployment.yaml"
sed -i.bak "s|{{SERVER_NAME}}|$SERVER_NAME|g" "$WORK_DIR/deployment.yaml"

echo "Configuring kubectl..."
gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$GCP_ZONE" --project "$GCP_PROJECT"

echo "Verifying cluster connectivity..."
kubectl cluster-info || { echo "ERROR: cannot reach cluster"; exit 1; }

echo "Applying manifests..."
kubectl apply -f "$WORK_DIR/namespace.yaml"
kubectl apply -f "$WORK_DIR/deployment.yaml"
kubectl apply -f "$WORK_DIR/service.yaml"
kubectl apply -f "$WORK_DIR/ingress.yaml"

echo "Waiting for rollout..."
if ! kubectl rollout status deployment/$APP_NAME -n $NAMESPACE --timeout=300s; then
  echo "ERROR: rollout failed. To roll back run:"
  echo "  kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
  exit 1
fi

kubectl get pods,svc,ingress -n $NAMESPACE

echo "Waiting for ingress IP (can take several minutes)..."
INGRESS_IP=""
for i in $(seq 1 30); do
  INGRESS_IP=$(kubectl get ingress ${APP_NAME}-ingress -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [ -n "$INGRESS_IP" ] && break
  sleep 10
done

if [ -n "$INGRESS_IP" ]; then
  echo "Application URL: http://$INGRESS_IP/"
else
  echo "Ingress IP not yet assigned. Check: kubectl get ingress -n $NAMESPACE"
fi

echo "Rollback if needed: kubectl rollout undo deployment/$APP_NAME -n $NAMESPACE"
