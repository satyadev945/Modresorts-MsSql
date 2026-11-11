# ModResorts – Deployment Guide (GCP GKE)

ModResorts is a Java 8 servlet WAR (`modresorts-2.0.0.war`, Maven, `javax.servlet`). It is packaged as a container that runs the WAR as the `ROOT` context on Apache Tomcat 9 (copied from `tomcat:9.0-jdk8-temurin`) on top of the requested runtime base image `openjdk:8-jdk`.

| Item | Value |
|------|-------|
| Build tool | Maven (`mvn clean package -DskipTests`) |
| Packaging | WAR, built from `WebContent/` and `src/` |
| Java | 8 |
| Port | 8080 (Tomcat default; the app has no port config file) |
| Health endpoint | `GET /health` → `{"status":"UP"}` (`HealthServlet`) |
| Env vars | `WEATHER_API_KEY`, `WEATHER_API_KEY_FILE`, `JNDI_INITIAL_CONTEXT_FACTORY`, `JNDI_PROVIDER_URL`, `SERVER_DISPLAY_NAME` |

## 1. Prerequisites
- Docker 20.10+
- Google Cloud SDK (`gcloud`) and `kubectl` (`gcloud components install kubectl gke-gcloud-auth-plugin`)
- A GCP project with billing, the Artifact Registry and GKE APIs enabled
- A GKE cluster (Standard or Autopilot) and an Artifact Registry Docker repository (or a Docker Hub account)

## 2. Local development with Docker Compose
```bash
export WEATHER_API_KEY=your-key      # optional
docker compose up --build
curl http://localhost:8080/health
```
`docker-compose.yml` defines only the application service; external services are configured via environment variables. Create a `config/` directory if you want to mount files (e.g. a key file referenced by `WEATHER_API_KEY_FILE=/config/weather.key`).

## 3. Build and push the image
From the repository root:
```bash
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
The script asks for the registry (1. Artifact Registry, 2. Docker Hub), credentials and tag (sanitised to lowercase, default `latest`), builds with `docker build -f Dockerfile -t <image> .` and pushes. Artifact Registry authentication uses `gcloud auth configure-docker <region>-docker.pkg.dev`.

Create an Artifact Registry repo if needed:
```bash
gcloud artifacts repositories create modresorts --repository-format=docker --location=us-central1
```

## 4. GKE setup
```bash
gcloud container clusters create modresorts-cluster --zone us-central1-a --num-nodes 2
gcloud container clusters get-credentials modresorts-cluster --zone us-central1-a --project <PROJECT_ID>
kubectl cluster-info
```
GKE nodes pull from Artifact Registry in the same project by default. For cross-project or Docker Hub private images, configure IAM or an image pull secret.

## 5. Deploy
```bash
./scripts/deploy-image.sh      # Linux/macOS
scripts\deploy-image.bat       # Windows
```
The script prompts for project, zone, cluster, image URI, namespace, ingress host and optional env vars. It renders the manifests (placeholders `{{IMAGE_URI}}`, `{{NAMESPACE}}`, `{{INGRESS_HOST}}`, `{{WEATHER_API_KEY}}`, `{{JNDI_INITIAL_CONTEXT_FACTORY}}`, `{{JNDI_PROVIDER_URL}}`, `{{SERVER_DISPLAY_NAME}}`) into a temporary directory, then applies them in order: namespace → deployment → service → ingress, waits for the rollout and prints resources and the ingress address.

### Manifests (`kubernetes/`)
- `namespace.yaml` – namespace (default `modresorts`)
- `deployment.yaml` – 2 replicas, rolling update, requests 250m/512Mi, limits 500m/1Gi, startup/liveness/readiness probes on `/health:8080`
- `service.yaml` – ClusterIP, port 80 → 8080
- `ingress.yaml` – GKE external HTTP(S) load balancer (`kubernetes.io/ingress.class: gce`)

The GCE ingress takes several minutes to provision. Check with `kubectl get ingress -n modresorts`. Point DNS for your host at the ingress IP, or test with `curl -H "Host: modresorts.example.com" http://<IP>/health`.

## 6. Scaling and management
```bash
kubectl scale deployment/modresorts --replicas=4 -n modresorts
kubectl autoscale deployment modresorts --cpu-percent=70 --min=2 --max=6 -n modresorts
kubectl set image deployment/modresorts modresorts=<new-image> -n modresorts   # rolling update
kubectl rollout history deployment/modresorts -n modresorts
kubectl rollout undo deployment/modresorts -n modresorts                       # rollback
```

## 7. Troubleshooting
| Symptom | Checks |
|---------|--------|
| `ImagePullBackOff` | Verify image URI/tag; grant `roles/artifactregistry.reader` to the node service account; `kubectl describe pod` |
| `CrashLoopBackOff` | `kubectl logs <pod> -n modresorts --previous`; check memory limit (JVM uses 75% of container memory) |
| `OOMKilled` | Increase memory limit or lower `-XX:MaxRAMPercentage` via `CATALINA_OPTS` |
| Pods not Ready | Probe `/health`; `kubectl port-forward deploy/modresorts 8080:8080` and curl it |
| Ingress 502 / backends UNHEALTHY | Wait for provisioning; confirm Service endpoints (`kubectl get endpoints -n modresorts`); GCE health check follows the readiness probe path |
| Ingress has no IP | `kubectl describe ingress -n modresorts`; confirm HTTP load balancing add-on is enabled |

## 8. Configuration and security
- Pass secrets (e.g. `WEATHER_API_KEY`) through Kubernetes Secrets or Secret Manager instead of plain values; the provided deployment uses plain env placeholders for simplicity. Example: `kubectl create secret generic modresorts-secrets --from-literal=WEATHER_API_KEY=... -n modresorts` and reference with `valueFrom.secretKeyRef`.
- The container runs as the non-root user `app` (uid 1001). No HEALTHCHECK or extra packages are included; Kubernetes probes handle health.
- `JNDI_PROVIDER_URL` is optional; if unset the RMI/JNDI context is skipped.
- Use Workload Identity for any GCP API access; avoid service account key files.
- Enable TLS on the ingress with a Google-managed certificate (`ManagedCertificate`) and restrict access with Cloud Armor if needed.

## 9. Java-specific notes
- JVM flags in `CATALINA_OPTS`: `-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError`, `TZ=UTC`, UTF-8 encoding.
- `WeatherServlet` uses CDI `@Inject` (`ModResortsCustomerInformation`), which is not provided by Tomcat; the field is unused so it remains null. Add a CDI implementation (e.g. Weld) if you start using it.
- `AvailabilityCheckerServlet` writes `reservations.zip` to `user.home` (`/home/app`, writable, ephemeral).
- Dependencies with known vulnerabilities (log4j-core 2.14.1, jackson-databind 2.9.10, commons-collections 3.2.1, Spring 5.3.17) should be upgraded.
- Runtime image `openjdk:8-jdk` is deprecated on Docker Hub; consider `eclipse-temurin:8-jre` for production.
