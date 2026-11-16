# ModResorts – Deployment Guide (Docker & Azure AKS)

## 1. Application Summary
- Spring Boot 2.7.18, Java 8 target, Maven, executable JAR (`target/modresorts-2.0.0.jar`)
- Port: `9080` (`server.port=${PORT:9080}`)
- Health: Spring Boot Actuator – `/actuator/health`, `/actuator/health/liveness`, `/actuator/health/readiness` (probes enabled in `application.properties`); a simple `/health` servlet also exists
- Optional env vars: `WEATHER_API_KEY`, `WEATHER_API_KEY_FILE` (default `/mnt/secrets-store/weather-api-key`), `SERVER_NAME`, `JNDI_INITIAL_CONTEXT_FACTORY`, `JNDI_PROVIDER_URL`
- Runtime base image: `eclipse-temurin:8-jdk` (explicit); builder `maven:3.9.4-eclipse-temurin-8`

## 2. Prerequisites
- Docker 20.10+ (and Docker Compose v2)
- Azure CLI (`az`), logged in with `az login`
- kubectl
- An Azure subscription, an AKS cluster, and an ACR (or Docker Hub account)
- AKS with the Application Gateway Ingress Controller (AGIC) add-on for the provided Ingress
- Attach ACR to AKS: `az aks update -g <rg> -n <cluster> --attach-acr <acr>`

## 3. Local Development with Docker Compose
```bash
docker compose up --build
# http://localhost:9080/  and  http://localhost:9080/actuator/health
```
Set `WEATHER_API_KEY` in your shell to enable the weather feature. Compose only runs the application; no databases or other infrastructure are included.

## 4. Build and Push the Image
Run from the repository root:
```bash
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
The script prompts for the image tag (default `latest`, sanitized to lowercase), the registry (1. Azure ACR, 2. Docker Hub) and credentials, then builds and pushes `<registry>/modresorts:<tag>`.

The Dockerfile is multi-stage: CSS purge (node) → Maven build (`mvn clean package -DskipTests`, no wrapper) → runtime (`eclipse-temurin:8-jdk`, non-root user `appuser`, UID 1001). It has no HEALTHCHECK; Kubernetes probes handle health.

## 5. Deploy to AKS
```bash
./scripts/deploy-image.sh      # Linux/macOS
scripts\deploy-image.bat       # Windows
```
The script prompts for resource group, cluster, image URI, namespace, ingress host and optional `WEATHER_API_KEY`. It replaces `{{IMAGE_URI}}`, `{{NAMESPACE}}`, `{{INGRESS_HOST}}`, `{{WEATHER_API_KEY}}` in a temporary copy of the manifests, runs `az aks get-credentials`, applies the manifests in order and waits for the rollout.

### Manifests (`kubernetes/`)
| File | Purpose |
|------|---------|
| `namespace.yaml` | Namespace (default `modresorts`) |
| `deployment.yaml` | 2 replicas, requests 250m/512Mi, limits 500m/1Gi, startup/liveness/readiness probes on port 9080 |
| `service.yaml` | ClusterIP, port 80 → 9080 |
| `ingress.yaml` | AGIC ingress (`azure/application-gateway`), host from `{{INGRESS_HOST}}` |

### Manual deployment
```bash
az aks get-credentials -g <rg> -n <cluster>
# replace placeholders first (use | as the sed delimiter)
sed -i 's|{{IMAGE_URI}}|myacr.azurecr.io/modresorts:latest|g; s|{{NAMESPACE}}|modresorts|g; s|{{INGRESS_HOST}}|modresorts.example.com|g; s|{{WEATHER_API_KEY}}||g' kubernetes/*.yaml
kubectl apply -f kubernetes/namespace.yaml
kubectl apply -f kubernetes/deployment.yaml
kubectl apply -f kubernetes/service.yaml
kubectl apply -f kubernetes/ingress.yaml
kubectl rollout status deployment/modresorts -n modresorts
```

## 6. Configuration Management
- Non-sensitive config: environment variables in `deployment.yaml`.
- Sensitive values (e.g. `WEATHER_API_KEY`): prefer a Kubernetes Secret or Azure Key Vault CSI driver mounted at `/mnt/secrets-store/weather-api-key` (the app reads it automatically via `WEATHER_API_KEY_FILE`) instead of plain env values.
- JVM tuning via `JAVA_OPTS` (default `-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Xms256m`).

## 7. Scaling and Management
```bash
kubectl scale deployment/modresorts -n modresorts --replicas=3
kubectl autoscale deployment/modresorts -n modresorts --cpu-percent=70 --min=2 --max=6
kubectl set image deployment/modresorts modresorts=<new-image> -n modresorts   # rolling update
kubectl rollout history deployment/modresorts -n modresorts
kubectl rollout undo deployment/modresorts -n modresorts                         # rollback
```

## 8. Troubleshooting
- **ImagePullBackOff**: ACR not attached to AKS, wrong image URI/tag. Run `kubectl describe pod`.
- **CrashLoopBackOff / OOMKilled**: check `kubectl logs`; raise memory limit or lower `MaxRAMPercentage`.
- **Readiness failing**: `kubectl port-forward deploy/modresorts 9080:9080 -n modresorts` then `curl localhost:9080/actuator/health/readiness`.
- **Service unreachable**: `kubectl get endpoints -n modresorts`; ensure selector `app=modresorts` matches pods.
- **Ingress has no address**: confirm AGIC is enabled (`az aks show -g <rg> -n <cluster> --query addonProfiles.ingressApplicationGateway`), and check `kubectl describe ingress`.
- **Slow startup**: startup probe allows ~160s before liveness takes over.

## 9. Security Considerations
- Container runs as non-root (UID 1001); consider adding `securityContext` and network policies.
- No secrets are baked into the image; use Kubernetes Secrets / Key Vault.
- Terminate TLS at Application Gateway; add `appgw.ingress.kubernetes.io/ssl-redirect: "true"` and a certificate.
- Known outdated dependencies in `pom.xml` (log4j-core 2.14.1, jackson-databind 2.9.10, commons-collections 3.2.1) carry known CVEs – upgrade before production use.
- Scan images (`az acr task`, Defender for Containers, Trivy).

## 10. Java-specific Notes
- The runtime image is the explicitly requested `eclipse-temurin:8-jdk` (a JDK, larger than a JRE image). `-XX:+UseContainerSupport` requires 8u191+, which current Temurin 8 images satisfy.
- The app writes `reservations.zip` to `user.home` (`/home/appuser`), which is writable in the container but ephemeral.
- Timezone is `UTC` (`TZ=UTC`), charset UTF-8.
