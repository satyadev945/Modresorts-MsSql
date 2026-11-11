#!/bin/bash
# Deploy ModResorts to GCP GKE.  Usage: ./scripts/deploy-image.sh
set -e
set -o pipefail

APP_NAME="modresorts"
NAMESPACE="modresorts"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_SRC="${SCRIPT_DIR}/../kubernetes"

for tool in gcloud kubectl; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: $tool is not installed or not on PATH."
    exit 1
  fi
done
if [ ! -d "$K8S_SRC" ]; then
  echo "ERROR: kubernetes manifests directory not found at $K8S_SRC"
  exit 1
fi

prompt_required() {
  local __var="$1" __msg="$2" __val=""
  while [ -z "$__val" ]; do
    read -r -p "$__msg" __val
    [ -z "$__val" ] && echo "  A value is required."
  done
  printf -v "$__var" '%s' "$__val"
}

prompt_required GCP_PROJECT "GCP project ID: "
prompt_required GCP_ZONE "GKE cluster zone or region (e.g. us-central1-a): "
prompt_required CLUSTER_NAME "GKE cluster name: "
prompt_required IMAGE_URI "Docker image URI (e.g. us-central1-docker.pkg.dev/PROJECT/REPO/modresorts:latest): "

read -r -p "Enter value for WEATHER_API_KEY (or press Enter to skip): " WEATHER_API_KEY
read -r -p "Enter value for WEATHER_GRPC_TARGET (host:port, or press Enter to skip): " WEATHER_GRPC_TARGET

# Work on a temporary copy so the repository manifests keep their {{PLACEHOLDERS}}
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
cp -R "$K8S_SRC/." "$WORK_DIR/"

for f in "$WORK_DIR"/*.yaml; do
  sed -i.bak "s|{{IMAGE_URI}}|${IMAGE_URI}|g" "$f"
  sed -i.bak "s|{{NAMESPACE}}|${NAMESPACE}|g" "$f"
  sed -i.bak "s|{{WEATHER_GRPC_TARGET}}|${WEATHER_GRPC_TARGET}|g" "$f"
  rm -f "$f.bak"
done

echo "Configuring kubectl for cluster ${CLUSTER_NAME}..."
gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$GCP_ZONE" --project "$GCP_PROJECT"

echo "Verifying cluster connectivity..."
kubectl cluster-info || exit 1

echo "Applying namespace..."
kubectl apply -f "$WORK_DIR/namespace.yaml"

if [ -n "$WEATHER_API_KEY" ]; then
  echo "Creating/updating secret modresorts-secrets..."
  kubectl create secret generic modresorts-secrets \
    --from-literal=WEATHER_API_KEY="$WEATHER_API_KEY" \
    -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
fi

echo "Applying deployment, service and ingress..."
kubectl apply -f "$WORK_DIR/deployment.yaml"
kubectl apply -f "$WORK_DIR/service.yaml"
kubectl apply -f "$WORK_DIR/ingress.yaml"

echo "Waiting for rollout..."
if ! kubectl rollout status deployment/${APP_NAME} -n ${NAMESPACE} --timeout=300s; then
  echo ""
  echo "ERROR: rollout failed. Inspect and roll back with:"
  echo "  kubectl describe pods -n ${NAMESPACE}"
  echo "  kubectl logs deployment/${APP_NAME} -n ${NAMESPACE}"
  echo "  kubectl rollout undo deployment/${APP_NAME} -n ${NAMESPACE}"
  exit 1
fi

echo ""
kubectl get pods,svc,ingress -n "$NAMESPACE"

echo ""
echo "Waiting for ingress IP (can take several minutes)..."
INGRESS_IP=""
for i in $(seq 1 30); do
  INGRESS_IP=$(kubectl get ingress modresorts-ingress -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [ -n "$INGRESS_IP" ] && break
  sleep 10
done

if [ -n "$INGRESS_IP" ]; then
  echo "Application URL: http://${INGRESS_IP}/resorts/"
  echo "Health URL:      http://${INGRESS_IP}/resorts/health"
else
  echo "Ingress IP not yet assigned. Check later: kubectl get ingress -n ${NAMESPACE}"
fi
echo ""
echo "Rollback if needed: kubectl rollout undo deployment/${APP_NAME} -n ${NAMESPACE}"
