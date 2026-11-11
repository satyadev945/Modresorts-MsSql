# ModResorts - Deployment Guide (Azure AKS)

## 1. Application Overview
- Spring Boot 2.6.6 (embedded Tomcat), Java 8, Maven, executable JAR (`target/modresorts-2.0.0.jar`)
- Port: `8080` (Spring Boot default; no `server.port` configured)
- Health endpoint: `GET /health` (custom `HealthServlet`, returns `{"status":"UP"}`). Actuator is not a dependency.
- Environment variables read by the app: `WEATHER_API_KEY`, `JMX_APPINFO_ENABLED`, `SERVER_NAME`/`HOSTNAME`
- SQL Server driver (`mssql-jdbc`) is on the classpath; the database is external and not part of these artifacts.
- Runtime base image: `eclipse-temurin:8-jdk-alpine` (explicit). Builder: `maven:3.9.4-eclipse-temurin-8`.

## 2. Prerequisites
- Docker 20+ and Docker Compose
- Azure CLI (`az`), `kubectl`, an Azure subscription
- An Azure Container Registry (or Docker Hub account) and an AKS cluster with the Application Gateway Ingress Controller (AGIC) enabled

## 3. Local Development with Docker Compose
```bash
export WEATHER_API_KEY=<your-key>   # optional
docker compose up --build
# open http://localhost:8080 and http://localhost:8080/health
```
The compose file contains only the application service. Provide external services via environment variables.

## 4. Build and Push the Image
Run from the repository root:
```bash
./scripts/build-push.sh          # Linux/macOS
scripts\build-push.bat           # Windows
```
The script prompts for a tag (default `latest`), registry type (1. ACR, 2. Docker Hub) and credentials, then builds and pushes. Note the printed image URI.

## 5. AKS Setup
```bash
az login
az aks create -g <rg> -n <cluster> --node-count 2 --enable-addons ingress-appgw --appgw-name <gw> --appgw-subnet-cidr 10.225.0.0/16 --generate-ssh-keys
az aks update -g <rg> -n <cluster> --attach-acr <acr-name>
az aks get-credentials -g <rg> -n <cluster>
```

## 6. Deploy to AKS
```bash
./scripts/deploy-image.sh        # or scripts\deploy-image.bat
```
The script prompts for resource group, cluster, image URI and optional env vars, substitutes `{{PLACEHOLDER}}` values in a temporary copy of the manifests, and applies them in order:
1. `kubernetes/namespace.yaml` - namespace `modresorts`
2. `kubernetes/deployment.yaml` - 2 replicas, probes on `/health:8080`, requests 250m/512Mi, limits 500m/1Gi
3. `kubernetes/service.yaml` - ClusterIP, port 80 -> 8080
4. `kubernetes/ingress.yaml` - AGIC ingress, host `modresorts.example.com` (edit to your domain)

Manual alternative: replace `{{IMAGE_URI}}` and other placeholders, then `kubectl apply -f kubernetes/`.

## 7. Troubleshooting
- Pods `ImagePullBackOff`: ensure ACR is attached (`az aks update --attach-acr`) and the image URI/tag is correct.
- Pods `CrashLoopBackOff`: `kubectl logs <pod> -n modresorts`; `kubectl describe pod <pod> -n modresorts`. Check memory (JVM heap 512m vs. limit 1Gi).
- Readiness failing: JVM start may be slow; raise `initialDelaySeconds`. Verify with `kubectl port-forward svc/modresorts-service 8080:80 -n modresorts` then `curl localhost:8080/health`.
- Ingress has no address: `kubectl describe ingress modresorts-ingress -n modresorts`; check AGIC pod logs in `kube-system`.
- 502 from App Gateway: confirm health probe path `/health` returns 200.

## 8. Scaling and Management
```bash
kubectl scale deployment/modresorts --replicas=3 -n modresorts
kubectl autoscale deployment modresorts --cpu-percent=70 --min=2 --max=6 -n modresorts
kubectl set image deployment/modresorts modresorts=<new-image> -n modresorts
kubectl rollout status deployment/modresorts -n modresorts
kubectl rollout undo deployment/modresorts -n modresorts
```

## 9. Configuration
| Variable | Purpose | Default |
|---|---|---|
| `SERVER_PORT` | HTTP port | 8080 |
| `WEATHER_API_KEY` | Weather API key | empty |
| `JMX_APPINFO_ENABLED` | Register AppInfo MBean | true |
| `JAVA_OPTS` | JVM flags | `-Xms256m -Xmx512m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0` |
| `SPRING_DATASOURCE_*` | External SQL Server connection | empty |

## 10. Security
- Container runs as non-root user `appuser`.
- Move secrets (API keys, DB password) to Kubernetes Secrets or Azure Key Vault (CSI driver) for production instead of plain env values.
- Add TLS to the ingress (cert-manager or Key Vault certificates).
- The pom uses log4j-core 2.14.1 (vulnerable to Log4Shell); upgrade to 2.17.1+ before production.

## 11. Java Notes
- Java 8 images: `-XX:+UseContainerSupport` is available in 8u191+.
- The app writes `reservations.zip` to `user.home` (`/home/appuser`).
- Wrapper scripts (mvnw/gradlew) are intentionally not used; the Docker build uses system `mvn`.
