# ModResorts - Deployment Guide (Docker and Azure AKS)

## 1. Application Overview
- Spring Boot 2.6.5, Java 8 (source/target 1.8), Maven, executable JAR (`modresorts-2.0.0.jar`)
- Port: 8080 (Spring Boot default; no `server.port` override exists)
- Health endpoint: `GET /health` (custom `HealthServlet`, returns `{"status":"UP"}`). Spring Boot Actuator is NOT a dependency.
- Optional environment variable: `WEATHER_API_KEY` (used by `WeatherServlet`)
- Runtime base image: `eclipse-temurin:8-jre` (explicit); builder: `maven:3.9.4-eclipse-temurin-8`

## 2. Prerequisites
- Docker 20.10+ (BuildKit enabled)
- Azure CLI 2.40+ and `kubectl`
- An Azure subscription, an AKS cluster, and a container registry (ACR or Docker Hub)
- AKS with Application Gateway Ingress Controller (AGIC) enabled

## 3. Local Development with Docker Compose
```bash
export WEATHER_API_KEY=<optional>
docker compose up --build
# open http://localhost:8080  and  http://localhost:8080/health
```
docker-compose.yml contains only the application service. Mount optional configuration into `./config`.

## 4. Build and Push the Image
Run from the repository root:
```bash
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
The script prompts for the tag (default `latest`), registry type (1 = ACR, 2 = Docker Hub) and credentials. ACR login uses `az acr login --name <acr>`. The image name is sanitized (lowercase, hyphenated).

## 5. Deploy to AKS
```bash
az login
./scripts/deploy-image.sh      # or scripts\deploy-image.bat
```
The script prompts for resource group, cluster name, image URI and `WEATHER_API_KEY`, replaces `{{IMAGE_URI}}`, `{{NAMESPACE}}` and `{{WEATHER_API_KEY}}` in a temporary copy of the manifests, fetches credentials (`az aks get-credentials`), applies manifests in order (namespace, deployment, service, ingress) and waits for rollout.

### Manifests (`kubernetes/`)
| File | Purpose |
|------|---------|
| namespace.yaml | `modresorts` namespace |
| deployment.yaml | 2 replicas, requests 250m/512Mi, limits 500m/1Gi, HTTP probes on `/health:8080` |
| service.yaml | ClusterIP, port 80 -> 8080 |
| ingress.yaml | AGIC ingress, host `modresorts.example.com` (change to your host) |

If the ACR is not attached to the cluster: `az aks update -g <rg> -n <cluster> --attach-acr <acr>`.

## 6. Verification
```bash
kubectl get pods,svc,ingress -n modresorts
kubectl logs deploy/modresorts -n modresorts
kubectl port-forward svc/modresorts-service 8080:80 -n modresorts
```

## 7. Scaling and Management
```bash
kubectl scale deployment/modresorts --replicas=4 -n modresorts
kubectl autoscale deployment/modresorts --cpu-percent=70 --min=2 --max=6 -n modresorts
kubectl set image deployment/modresorts modresorts=<new-image> -n modresorts
kubectl rollout status deployment/modresorts -n modresorts
kubectl rollout undo deployment/modresorts -n modresorts
```

## 8. Troubleshooting
- **ImagePullBackOff**: verify image URI, registry permissions (attach ACR) or create an imagePullSecret for Docker Hub private repos.
- **CrashLoopBackOff**: `kubectl logs <pod> -n modresorts --previous`; check memory limit vs JVM settings.
- **Probe failures**: JVM start can take 30-40s; adjust `initialDelaySeconds`. Test `/health` via port-forward.
- **Ingress has no address / 502**: confirm AGIC addon is enabled, `kubectl describe ingress modresorts-ingress -n modresorts`, check service endpoints (`kubectl get endpoints -n modresorts`).
- **Service unreachable**: confirm selector `app: modresorts` matches pod labels.

## 9. Configuration
| Variable | Default | Description |
|----------|---------|-------------|
| SERVER_PORT | 8080 | HTTP port |
| SPRING_PROFILES_ACTIVE | docker | Spring profile |
| JAVA_OPTS | `-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Xms256m` | JVM options |
| TZ | UTC | Timezone |
| WEATHER_API_KEY | (empty) | Weather API key |

Java 8u191+ is container aware; `MaxRAMPercentage` is honored by `eclipse-temurin:8-jre`.

## 10. Security Considerations
- Container runs as non-root user (uid 1001).
- Store `WEATHER_API_KEY` in a Kubernetes Secret (or Azure Key Vault CSI driver) for production instead of a plain env value.
- Enable TLS on the ingress (cert-manager or Key Vault certificates) and replace the example host.
- The project depends on outdated libraries (e.g. log4j-core 2.14.1, which is vulnerable to Log4Shell; commons-collections 3.2.1); upgrade before production use. Java 8 is also at end of active support - consider moving to 17+.
- Wrapper scripts (mvnw/gradlew) are intentionally excluded; the build uses system `mvn`.

## 11. Technology Notes
- The Dockerfile uses a PurgeCSS stage (node) to prune `styles.css` before the Maven build.
- `mvn dependency:go-offline` is run after copying only `pom.xml` to cache dependencies.
- No HEALTHCHECK in the image: Kubernetes probes handle health.
