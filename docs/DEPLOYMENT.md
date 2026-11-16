# ModResorts – Deployment Guide (Docker & GCP GKE)

## Application summary
- Spring Boot 2.7.18, Java 8, Maven, executable JAR (`target/modresorts.jar`)
- Port: 8080 (Spring Boot default; no `server.port` override)
- Health endpoint: `GET /health` (custom `HealthServlet`, returns `{"status":"UP"}`); Actuator is not present
- Optional env vars: `WEATHER_API_KEY`, `GRPC_SERVICE_TARGET`, `SERVER_NAME`
- Runtime base image: `eclipse-temurin:8-jdk-alpine` (explicit)

## Prerequisites
- Docker 20+, Google Cloud SDK (`gcloud`), `kubectl`, `gke-gcloud-auth-plugin`
- A GCP project with billing, Artifact Registry and GKE APIs enabled

## Local development with Docker Compose
```bash
export WEATHER_API_KEY=your-key   # optional
docker compose up --build
# open http://localhost:8080/  and  http://localhost:8080/health
```

## Build and push the image
Run from the repository root:
```bash
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
Choose Google Artifact Registry (create the repo first:
`gcloud artifacts repositories create REPO --repository-format=docker --location=REGION`) or Docker Hub.
Tags are lower-cased and sanitized; empty tag defaults to `latest`.

## GKE cluster setup
```bash
gcloud container clusters create modresorts-cluster --zone us-central1-a --num-nodes 2
gcloud container clusters get-credentials modresorts-cluster --zone us-central1-a --project PROJECT_ID
```
Ensure the node service account can pull from Artifact Registry (`roles/artifactregistry.reader`).

## Deploy
```bash
./scripts/deploy-image.sh      # or scripts\deploy-image.bat
```
The script prompts for project, zone, cluster, image URI and optional env vars, substitutes
`{{IMAGE_URI}}`, `{{WEATHER_API_KEY}}`, `{{GRPC_SERVICE_TARGET}}`, `{{SERVER_NAME}}` in a temporary copy of the manifests and applies them in order:
namespace → deployment → service → ingress, then waits for rollout.

Manifests (`kubernetes/`):
- `namespace.yaml` – namespace `modresorts`
- `deployment.yaml` – 2 replicas, requests 250m/512Mi, limits 500m/1Gi, HTTP probes on `/health:8080`
- `service.yaml` – ClusterIP 80 → 8080 with NEG annotation for GKE Ingress
- `ingress.yaml` – GCE external HTTP(S) load balancer

Access: `kubectl get ingress -n modresorts` and open `http://<ADDRESS>/` (provisioning can take 5–10 minutes).
Edit `ingress.yaml` to add a `host` and TLS (ManagedCertificate) for production.

## Scaling and management
```bash
kubectl scale deployment/modresorts -n modresorts --replicas=3
kubectl autoscale deployment modresorts -n modresorts --cpu-percent=70 --min=2 --max=6
kubectl set image deployment/modresorts modresorts=NEW_IMAGE -n modresorts
kubectl rollout status deployment/modresorts -n modresorts
kubectl rollout undo deployment/modresorts -n modresorts
```

## Troubleshooting
- Pods `ImagePullBackOff`: check image URI and Artifact Registry permissions.
- Pods `CrashLoopBackOff`: `kubectl logs -n modresorts deploy/modresorts --previous`; check memory limit vs. JAVA_OPTS.
- Probes failing: increase `initialDelaySeconds`; verify `kubectl port-forward -n modresorts deploy/modresorts 8080:8080` then `curl localhost:8080/health`.
- Ingress shows no address / 502: `kubectl describe ingress -n modresorts`; the GCE health check must succeed on `/health` (wait a few minutes).
- Service has no endpoints: `kubectl get endpoints -n modresorts`; check selector labels `app=modresorts`.

## Configuration and security
- Pass secrets (e.g. `WEATHER_API_KEY`) via Kubernetes Secrets rather than plain env values for production.
- The container runs as a non-root user; no extra packages are installed in the runtime image.
- JVM flags are set through `JAVA_OPTS` (container-aware, `MaxRAMPercentage=75`, `TZ=UTC`).
- Note: the project's dependencies include outdated libraries (log4j-core 2.14.1, jackson-databind 2.9.10, commons-collections 3.2.1) with known vulnerabilities; upgrade before production.
- The Dockerfile has no HEALTHCHECK; Kubernetes probes handle health checking.
