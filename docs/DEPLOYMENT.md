# ModResorts – Deployment Guide (Docker & GCP GKE)

## 1. Application overview
- WAR-packaged Java EE (Servlet 3.1) application, Java 8, Maven (`pom.xml`, artifact `modresorts-2.0.0.war`).
- Runs on Apache Tomcat 9 inside an `amazoncorretto:8` runtime image (explicit base image). The WAR is deployed as `ROOT.war`.
- Port: **8080**. Health endpoint: **`/health`** (`HealthServlet`, returns `{"status":"UP"}`).
- Optional environment variables: `WEATHER_API_KEY`, `REMOTE_SERVICE_GRPC_TARGET`, `SERVER_NAME`.

## 2. Prerequisites
- Docker 20.10+, gcloud CLI, kubectl (+ `gke-gcloud-auth-plugin`), a GCP project with billing, Artifact Registry and GKE enabled.

## 3. Local run with Docker Compose
```bash
docker compose up --build
# http://localhost:8080/   health: http://localhost:8080/health
```
Set optional variables in the shell or an `.env` file (e.g. `WEATHER_API_KEY=...`). Only the application service is defined; external services must be provided separately.

## 4. Build and push the image
Run from the repository root:
```bash
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
Choose Google Artifact Registry or Docker Hub. Image names/tags are sanitised (lowercase, hyphenated, default tag `latest`). Create the Artifact Registry repo first if needed:
```bash
gcloud artifacts repositories create modresorts --repository-format=docker --location=us-central1
```

## 5. GKE cluster setup
```bash
gcloud container clusters create modresorts-cluster --zone us-central1-a --num-nodes 2
# or Autopilot:
gcloud container clusters create-auto modresorts-cluster --region us-central1
gcloud container clusters get-credentials modresorts-cluster --zone us-central1-a --project <PROJECT_ID>
```
Ensure nodes can pull from Artifact Registry (default compute service account has reader access in the same project).

## 6. Deploy to GKE
```bash
./scripts/deploy-image.sh      # or scripts\deploy-image.bat
```
The script prompts for project, zone, cluster, image URI and optional env values, substitutes `{{IMAGE_URI}}` and env placeholders in a temporary copy of the manifests, applies them in order (namespace → deployment → service → ingress), waits for the rollout and prints the ingress IP.

Manifests (`kubernetes/`):
| File | Purpose |
|------|---------|
| namespace.yaml | `modresorts` namespace |
| deployment.yaml | 2 replicas, 250m/512Mi requests, 500m/1Gi limits, startup/liveness/readiness probes on `/health:8080` |
| service.yaml | ClusterIP, port 80 → 8080 (NEG enabled) |
| ingress.yaml | GCE external HTTP(S) load balancer |

The GCE ingress can take 5–10 minutes to provision. Add a `host` rule, a static IP (`kubernetes.io/ingress.global-static-ip-name`) and a ManagedCertificate for HTTPS in production.

## 7. Operations
```bash
kubectl get pods,svc,ingress -n modresorts
kubectl logs -f deployment/modresorts -n modresorts
kubectl scale deployment/modresorts --replicas=4 -n modresorts
kubectl autoscale deployment modresorts --cpu-percent=70 --min=2 --max=6 -n modresorts
kubectl set image deployment/modresorts modresorts=<NEW_IMAGE_URI> -n modresorts   # rolling update
kubectl rollout undo deployment/modresorts -n modresorts                            # rollback
```

## 8. Troubleshooting
- **ImagePullBackOff**: check the image URI and Artifact Registry permissions (`roles/artifactregistry.reader`).
- **CrashLoopBackOff / OOMKilled**: `kubectl describe pod`, `kubectl logs --previous`; raise memory limit (JVM uses 75% of container memory).
- **Probes failing**: confirm `curl` to `/health` via `kubectl port-forward deployment/modresorts 8080:8080`. Tomcat takes ~15–30 s to start.
- **Ingress 502 / backends UNHEALTHY**: wait for provisioning; verify the health check path in the load balancer is `/health` (use a BackendConfig if needed) and the service selector matches pod labels.
- **No weather data**: `WEATHER_API_KEY` empty → app serves default sample data (expected).

## 9. Configuration & security
- Pass secrets (e.g. `WEATHER_API_KEY`) via Kubernetes Secrets / Secret Manager in production rather than plain env values.
- Container runs as non-root UID 1001; no package managers or health-check tools are installed in the runtime image.
- Dependencies in `pom.xml` include outdated libraries (log4j-core 2.14.1, jackson-databind 2.9.10, spring 5.3.x, commons-collections 3.2.1) with known CVEs – upgrade them before production use.
- Application form-login/security constraints are disabled in `web.xml` (demo setup).
- `SSLUtils`/`FakeX509TrustManager` disable certificate validation – do not use in production.

## 10. Java notes
- JVM flags: `-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Duser.timezone=UTC -Dfile.encoding=UTF-8 -Duser.home=/home/app` (override with `JAVA_OPTS`). `user.home` is writable because the app writes `reservations.zip` there.
- The Maven wrapper/Gradle wrapper are not used; the image builds with system `mvn`.
- `cloudbuild.yaml` (PurgeCSS + docker build) can still be used with Cloud Build; it builds from the same Dockerfile.
