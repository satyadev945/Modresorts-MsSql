# ModResorts – Deployment Guide (Docker & Azure AKS)

## 1. Application summary
- Spring Boot 2.7.18, Maven, Java 8, executable JAR (`target/modresorts-2.0.0.jar`)
- Port: **8080** (Spring Boot default; no `server.port` override)
- Health endpoint: `GET /health` (`HealthServlet`, returns `{"status":"UP"}`); no Actuator dependency
- Environment variables used by the code: `WEATHER_API_KEY`, `WEATHER_API_KEY_FILE`, `SERVER_DISPLAY_NAME`, `SERVER_FULL_NAME`, `WEATHER_SERVICE_GRPC_ENDPOINT`
- Runtime base image: `amazoncorretto:8` (explicit); builder: `maven:3.9.4-eclipse-temurin-8`

## 2. Prerequisites
Docker 20+, Azure CLI 2.40+, kubectl, an Azure subscription, an AKS cluster with the Application Gateway Ingress Controller (AGIC) add-on, and an ACR (or Docker Hub account).

## 3. Local run with Docker Compose
```bash
export WEATHER_API_KEY=<optional>
docker compose up --build
curl http://localhost:8080/health
```
Only the application service is defined; provide any external services through environment variables.

## 4. Build and push
```bash
./scripts/build-push.sh      # Linux/macOS
scripts\build-push.bat       # Windows
```
Run from the repository root. Choose ACR or Docker Hub, enter a tag (default `latest`; names are lower-cased and sanitised). The script logs in (`az acr login --name <acr>` for ACR), builds and pushes.

## 5. AKS deployment
```bash
az login
az aks get-credentials --resource-group <rg> --name <cluster>
./scripts/deploy-image.sh     # or scripts\deploy-image.bat
```
The script prompts for resource group, cluster, image URI and optional env values, substitutes `{{IMAGE_URI}}`, `{{WEATHER_API_KEY}}`, `{{SERVER_DISPLAY_NAME}}`, `{{WEATHER_SERVICE_GRPC_ENDPOINT}}` in a temporary copy of the manifests, applies them in order (namespace → deployment → service → ingress) and waits for rollout.

Manifests (`kubernetes/`):
| File | Purpose |
|---|---|
| namespace.yaml | `modresorts` namespace |
| deployment.yaml | 2 replicas, requests 250m/512Mi, limits 500m/1Gi, startup/liveness/readiness probes on `/health:8080` |
| service.yaml | ClusterIP `modresorts-service`, 80 → 8080 |
| ingress.yaml | AGIC ingress, host `modresorts.example.com` (change to your domain) |

Pulling from ACR: `az aks update -n <cluster> -g <rg> --attach-acr <acr>`.

## 6. Scaling and management
```bash
kubectl scale deployment/modresorts -n modresorts --replicas=4
kubectl autoscale deployment modresorts -n modresorts --cpu-percent=70 --min=2 --max=6
kubectl set image deployment/modresorts modresorts=<new-image> -n modresorts
kubectl rollout status deployment/modresorts -n modresorts
kubectl rollout undo deployment/modresorts -n modresorts
```

## 7. Troubleshooting
- **Pod CrashLoopBackOff / not ready**: `kubectl logs deploy/modresorts -n modresorts`, `kubectl describe pod -n modresorts`. Increase `startupProbe.failureThreshold` for slow starts.
- **ImagePullBackOff**: verify image URI and that ACR is attached to AKS (or create an imagePullSecret for Docker Hub private repos).
- **OOMKilled**: raise memory limit; JVM uses `MaxRAMPercentage=75`.
- **Service unreachable**: `kubectl get endpoints -n modresorts`; check selector `app: modresorts`.
- **Ingress has no address**: confirm AGIC is enabled (`az aks show ... --query addonProfiles`) and `kubectl describe ingress -n modresorts`.
- Quick test: `kubectl port-forward svc/modresorts-service 8080:80 -n modresorts`.

## 8. Configuration & security
- Do not store secrets in manifests for production: use Kubernetes Secrets or Azure Key Vault with the CSI Secrets Store driver (the app also supports `WEATHER_API_KEY_FILE` to read a mounted secret file).
- The container runs as non-root UID 1001; no HEALTHCHECK or extra packages are installed in the image.
- Enable TLS on the ingress (Key Vault certificate or cert-manager).
- Known dependency concerns in `pom.xml` (e.g. log4j-core 2.14.1, jackson-databind 2.9.10, commons-collections 3.2.1) have known CVEs; upgrade them before production.
- Java notes: Java 8 with `-XX:+UseContainerSupport` (requires 8u191+, satisfied by Corretto 8). Timezone is UTC.
