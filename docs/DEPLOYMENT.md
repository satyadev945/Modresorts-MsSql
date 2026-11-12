# ModResorts – Deployment Guide (Docker & Azure AKS)

## 1. Overview
ModResorts is a Spring Boot 2.7.18 / Java 8 web application (Maven, executable JAR `modresorts-2.0.0.jar`) serving servlets and static content on port **8080**. Health endpoint: `GET /health` (returns `{"status":"UP"}`). No Spring Actuator is present, so probes use `/health`.

## 2. Prerequisites
- Docker 20.10+ (BuildKit)
- Azure CLI 2.40+ (`az login`), kubectl, an Azure subscription
- An ACR (or Docker Hub account) and an AKS cluster with Application Gateway Ingress Controller (AGIC)
- Tip: `az aks update -n <cluster> -g <rg> --attach-acr <acr>` lets AKS pull from ACR

## 3. Local development with Docker Compose
```bash
docker compose up --build
# http://localhost:8080/  and  http://localhost:8080/health
```
Optional env vars: `WEATHER_API_KEY`, `WEATHER_API_KEY_FILE`, `JNDI_INITIAL_CONTEXT_FACTORY`, `JNDI_PROVIDER_URL`. Only the app container is defined; external services are supplied via env vars.

## 4. Build & push
Run from the repository root:
```bash
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
You are prompted for a tag (sanitised to lowercase, default `latest`) and a registry (1. ACR, 2. Docker Hub). The script prints the final image URI.

The Dockerfile has three stages: PurgeCSS (node:20-alpine) → Maven build (`maven:3.9.4-eclipse-temurin-8`) → runtime (`eclipse-temurin:8-jdk-alpine`, non-root user `appuser`, uid 1001). No HEALTHCHECK is baked in; Kubernetes probes handle it.

## 5. Deploy to AKS
```bash
./scripts/deploy-image.sh      # Linux/macOS
scripts\deploy-image.bat       # Windows
```
The script prompts for resource group, cluster name, image URI, ingress host and optional environment variables; renders `{{PLACEHOLDER}}` values into a temporary copy of `kubernetes/*.yaml` (sed with `|` delimiter), runs `az aks get-credentials`, applies namespace → deployment → service → ingress, waits for the rollout and prints the resources.

Manifests (`kubernetes/`):
| File | Purpose |
|------|---------|
| namespace.yaml | Namespace `modresorts` |
| deployment.yaml | 2 replicas, 250m/512Mi requests, 500m/1Gi limits, `/health` liveness & readiness probes on 8080 |
| service.yaml | ClusterIP `modresorts-service` 80 → 8080 |
| ingress.yaml | AGIC (`azure/application-gateway`) routing `/` to the service |

Manual apply: replace `{{IMAGE_URI}}`, `{{INGRESS_HOST}}`, `{{WEATHER_API_KEY}}`, `{{WEATHER_API_KEY_FILE}}`, `{{JNDI_INITIAL_CONTEXT_FACTORY}}`, `{{JNDI_PROVIDER_URL}}` first.

## 6. Configuration
| Variable | Purpose |
|----------|---------|
| SERVER_PORT | HTTP port (default 8080) |
| SPRING_PROFILES_ACTIVE | `docker` |
| JAVA_OPTS | `-XX:MaxRAMPercentage=75.0 -Duser.timezone=UTC ...` |
| WEATHER_API_KEY | Weather API key (fallback) |
| WEATHER_API_KEY_FILE | Path to a mounted secret (default `/mnt/secrets-store/weather-api-key`, e.g. Key Vault CSI driver) |
| JNDI_INITIAL_CONTEXT_FACTORY / JNDI_PROVIDER_URL | Optional JNDI settings |

## 7. Scaling & management
```bash
kubectl scale deployment/modresorts -n modresorts --replicas=4
kubectl autoscale deployment/modresorts -n modresorts --cpu-percent=70 --min=2 --max=6
kubectl set image deployment/modresorts modresorts=<new-image> -n modresorts   # rolling update
kubectl rollout undo deployment/modresorts -n modresorts                       # rollback
```

## 8. Troubleshooting
- **ImagePullBackOff**: verify the image URI and that AKS is attached to ACR; `kubectl describe pod`.
- **CrashLoopBackOff / probe failures**: `kubectl logs -l app=modresorts -n modresorts`; the JVM needs ~30–60 s to start (probe initial delays are set accordingly). Increase memory limit on OOMKilled.
- **Service unreachable**: `kubectl get endpoints -n modresorts`; selector must match `app: modresorts`.
- **Ingress has no address**: check AGIC pod logs in `kube-system` and that the add-on is enabled (`az aks enable-addons -a ingress-appgw ...`); ensure DNS for the ingress host points to the gateway IP.

## 9. Security
- Container runs as non-root (uid 1001); keep secrets out of manifests – prefer Azure Key Vault + Secrets Store CSI driver (`WEATHER_API_KEY_FILE`) over plain env values.
- Dependencies of note: `log4j-core 2.14.1` and `commons-collections 3.2.1` are outdated with known CVEs; upgrade them.
- Use private registries, network policies and TLS on the ingress.

## 10. Java notes
Java 8 uses `-XX:+UseContainerSupport` (8u191+). The app writes `reservations.zip` to `user.home` (`/home/appuser`), which is writable in the image. Heap is 75% of the container memory limit.
