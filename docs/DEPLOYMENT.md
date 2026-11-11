# ModResorts – Deployment Guide (Docker & GCP GKE)

## 1. Application overview
- Java EE / Servlet web application (WAR, Maven, Java 8), context root `/resorts`.
- Runtime: Apache Tomcat 9 (javax.servlet) running on `openjdk:8-jdk` (explicit base image), port **8080**.
- Health endpoint: `GET /resorts/health` → `{"status":"UP"}` (HealthServlet). Used for liveness, readiness, startup probes and the GKE load balancer health check.
- No database is required (the JNDI datasource is disabled in code).
- Configuration (environment variables): `WEATHER_API_KEY` (optional, real-time weather; default data otherwise), `WEATHER_GRPC_TARGET` (optional `host:port`), `SERVER_NAME` (optional).
- The reservation export writes `reservations.zip` to the user home (`/home/app`).

## 2. Prerequisites
Docker 20.10+, Google Cloud SDK (`gcloud`), `kubectl` (+ `gke-gcloud-auth-plugin`), a GCP project with billing, Artifact Registry and GKE APIs enabled.

## 3. Local run with Docker Compose
```bash
export WEATHER_API_KEY=   # optional
docker compose up --build
# open http://localhost:8080/resorts/  and  http://localhost:8080/resorts/health
```
Only the application service is defined; external services are supplied through environment variables.

Note: `cloudbuild.yaml` runs PurgeCSS on `WebContent/styles.css` before `docker build`; the Dockerfile copies `WebContent` as-is.

## 4. Build and push the image
Run from the repository root:
```bash
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
Choose 1 (Google Artifact Registry) or 2 (Docker Hub). Image names/tags are sanitized (lowercase, hyphenated, default tag `latest`). For Artifact Registry create the repository first:
```bash
gcloud artifacts repositories create modresorts --repository-format=docker --location=us-central1
```

## 5. GKE cluster setup
```bash
gcloud container clusters create-auto modresorts-cluster --region us-central1
gcloud container clusters get-credentials modresorts-cluster --region us-central1
```
Ensure the cluster nodes can pull from Artifact Registry (same project works by default).

## 6. Deploy to GKE
```bash
./scripts/deploy-image.sh       # or scripts\deploy-image.bat
```
The script prompts for project, zone/region, cluster, image URI, and optional `WEATHER_API_KEY` / `WEATHER_GRPC_TARGET`; substitutes `{{IMAGE_URI}}`, `{{NAMESPACE}}`, `{{WEATHER_GRPC_TARGET}}` in a temporary copy of the manifests; applies them in order; waits for rollout; and prints the ingress URL (`http://<IP>/resorts/`).

Manifests (`kubernetes/`):
| File | Purpose |
|------|---------|
| namespace.yaml | Namespace `modresorts` |
| deployment.yaml | 2 replicas, probes on `/resorts/health`, requests 250m/512Mi, limits 500m/1Gi, non-root (uid 1001); `WEATHER_API_KEY` read from optional secret `modresorts-secrets` |
| service.yaml | ClusterIP service (80→8080) + `BackendConfig` (health check, cookie session affinity) |
| ingress.yaml | GCE external HTTP(S) ingress, path `/` (root redirects to `/resorts/`) |

## 7. Scaling and management
```bash
kubectl scale deployment/modresorts -n modresorts --replicas=4
kubectl autoscale deployment modresorts -n modresorts --cpu-percent=70 --min=2 --max=6
kubectl set image deployment/modresorts modresorts=<new-image> -n modresorts
kubectl rollout status deployment/modresorts -n modresorts
kubectl rollout undo deployment/modresorts -n modresorts
```

## 8. Troubleshooting
- **ImagePullBackOff**: check the image URI and Artifact Registry permissions (`roles/artifactregistry.reader`).
- **CrashLoopBackOff / probe failures**: `kubectl logs deploy/modresorts -n modresorts`; `kubectl describe pod`. Startup allows up to 3 minutes.
- **Ingress 502 / unhealthy backend**: wait 5-10 minutes after creation; verify `kubectl describe ingress -n modresorts` and that the BackendConfig health check path is `/resorts/health`.
- **404 at `/`**: use `/resorts/`; `/` redirects there through the ROOT webapp.
- **Pending pods**: insufficient quota/resources; `kubectl describe pod`.

## 9. Configuration and security
- Pass the API key through a Kubernetes Secret (created by the deploy script) rather than plain manifest values; consider Secret Manager with the CSI driver.
- Container runs as non-root, with no extra packages or HEALTHCHECK; probes are handled by Kubernetes.
- `log4j-core 2.14.1`, `jackson-databind 2.9.10`, `commons-collections 3.2.1` and `spring-webmvc 5.3.17` in `pom.xml` have known CVEs; upgrade before production use.
- Restrict ingress with HTTPS (ManagedCertificate / FrontendConfig) before exposing publicly.

## 10. Java-specific notes
- JVM flags: `-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Xms256m` (set through `JAVA_OPTS`, honored by `catalina.sh`). Keep the container memory limit ≥ 1Gi.
- Timezone `UTC`, charset UTF-8. Tomcat handles SIGTERM for graceful shutdown (30s grace period).
- Session state is in-memory; the load balancer uses cookie affinity. Externalize state (e.g. Memorystore Redis) for true statelessness.
- Maven wrapper/Gradle wrapper files are intentionally excluded from the image build (`mvn` from the builder image is used).
