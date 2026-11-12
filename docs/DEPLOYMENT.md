# ModResorts – Deployment Guide (Azure AKS)

## 1. Overview
ModResorts is a Spring Boot 2.7.18 (Java 8, Maven, executable JAR) web application. It listens on port **8080** and exposes a health endpoint at **`/health`** (`HealthServlet`, returns `{"status":"UP"}`). Spring Boot Actuator is not included, so `/actuator/health` is not available.

Runtime image: `eclipse-temurin:8-jre` (explicit base image). Builder image: `maven:3.9.4-eclipse-temurin-8`.

## 2. Prerequisites
- Docker 20+ (and Docker Compose v2 for local runs)
- Azure CLI (`az`) logged in: `az login`
- kubectl (`az aks install-cli`)
- An Azure subscription, an AKS cluster and a container registry (ACR or Docker Hub)
- AKS Application Gateway Ingress Controller (AGIC) enabled: `az aks enable-addons -a ingress-appgw ...`
- If using ACR: attach it to AKS: `az aks update -g <rg> -n <cluster> --attach-acr <acr>`

## 3. Local development with Docker Compose
```bash
export WEATHER_API_KEY=<optional>
docker compose up --build
# browse http://localhost:8080  and  http://localhost:8080/health
```
Only the application service is defined. External services are not included.

## 4. Build and push the image
From the repository root:
```bash
./scripts/build-push.sh          # Linux/macOS
scripts\build-push.bat           # Windows
```
The script prompts for tag (default `latest`), registry (1 = ACR, 2 = Docker Hub) and credentials, builds with `docker build -f Dockerfile -t <registry>/modresorts:<tag> .`, and pushes.

## 5. Deploy to AKS
```bash
./scripts/deploy-image.sh        # Linux/macOS
scripts\deploy-image.bat         # Windows
```
The script prompts for resource group, cluster name, image URI and the optional environment variables, substitutes placeholders in a temporary copy of `kubernetes/`, runs `az aks get-credentials`, applies manifests in order (namespace → deployment → service → ingress), waits for rollout and prints the resources and ingress address.

### Manifests
| File | Purpose |
|------|---------|
| `kubernetes/namespace.yaml` | Namespace `modresorts` |
| `kubernetes/deployment.yaml` | 2 replicas, probes on `/health`, requests 250m/512Mi, limits 500m/1Gi |
| `kubernetes/service.yaml` | ClusterIP, port 80 → 8080 |
| `kubernetes/ingress.yaml` | AGIC ingress, host `modresorts.example.com` (edit to your DNS name) |

## 6. Configuration
| Variable | Description |
|----------|-------------|
| `WEATHER_API_KEY` | API key used by `WeatherServlet` (optional – default data is used otherwise) |
| `WEATHER_JMX_ENABLED` | Enable JMX MBean registration (`true`/`false`) |
| `SPRING_PROFILES_ACTIVE` | `docker` |
| `SERVER_PORT` | `8080` |
| `JAVA_OPTS` | JVM flags (container-aware, `MaxRAMPercentage=75`) |

For secrets such as `WEATHER_API_KEY`, prefer a Kubernetes Secret (`kubectl create secret generic ...` and `valueFrom.secretKeyRef`) or Azure Key Vault CSI driver in production.

The application is stateless; any shared state must be stored externally (e.g. Azure Cache for Redis), allowing replicas to scale freely.

## 7. Verification
```bash
kubectl get pods,svc,ingress -n modresorts
kubectl port-forward svc/modresorts-service 8080:80 -n modresorts
curl http://localhost:8080/health
```

## 8. Scaling and management
```bash
kubectl scale deployment/modresorts --replicas=3 -n modresorts
kubectl autoscale deployment/modresorts --cpu-percent=70 --min=2 --max=6 -n modresorts
kubectl set image deployment/modresorts modresorts=<new-image> -n modresorts   # rolling update
kubectl rollout history deployment/modresorts -n modresorts
kubectl rollout undo deployment/modresorts -n modresorts                         # rollback
```

## 9. Troubleshooting
- **ImagePullBackOff**: verify the image URI and that ACR is attached to AKS (`az aks check-acr`).
- **CrashLoopBackOff / OOMKilled**: `kubectl logs <pod> -n modresorts --previous`; raise memory limit or lower `MaxRAMPercentage`.
- **Readiness failing**: `kubectl describe pod <pod> -n modresorts`; confirm `/health` responds on 8080.
- **Service unreachable**: `kubectl get endpoints modresorts-service -n modresorts` must list pod IPs.
- **Ingress has no address**: check AGIC pod logs (`kubectl logs -n kube-system -l app=ingress-appgw`) and that the add-on is enabled.

## 10. Security
- Container runs as non-root user `appuser` (uid 1001).
- No package managers or extra tooling in the runtime image; no Dockerfile HEALTHCHECK (Kubernetes probes are used).
- Maven/Gradle wrappers are excluded from the build context via `.dockerignore`.
- Note: the project's dependencies (log4j-core 2.14.1, jackson-databind 2.9.10, commons-collections 3.2.1) have known vulnerabilities; upgrade them before production use.
- Use HTTPS/TLS on the ingress (cert-manager or Application Gateway certificates).

## 11. Java notes
- Java 8 uses `-XX:+UseContainerSupport` (available since 8u191) with `MaxRAMPercentage`.
- Built with `mvn clean package -DskipTests`; the Spring Boot plugin produces `target/modresorts-2.0.0.jar`.
- Timezone is UTC, charset UTF-8.
