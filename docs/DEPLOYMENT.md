# ModResorts (Eksa) - Deployment Guide for Azure AKS

## Application overview
- Spring Boot 2.7.18, Java 8, Maven, executable JAR (`target/modresorts.jar`)
- Embedded Tomcat on port **8080** (Spring Boot default; no `server.port` override)
- Health endpoint: `GET /health` (servlet returning `{"status":"UP"}`); Actuator is not used
- Optional env vars: `WEATHER_API_KEY`, `WEATHER_API_KEY_FILE`, `POD_NAME`, `JNDI_INITIAL_CONTEXT_FACTORY`, `JNDI_PROVIDER_URL`

## Prerequisites
- Docker 20+, Azure CLI 2.40+, kubectl, an Azure subscription
- An AKS cluster with the Application Gateway Ingress Controller (AGIC) add-on, and an ACR (or Docker Hub account)
- Attach ACR to AKS: `az aks update -g <rg> -n <cluster> --attach-acr <acr>`

## Local development
```bash
export WEATHER_API_KEY=<optional>
docker compose up --build
# http://localhost:8080  and  http://localhost:8080/health
```

## Build and push
Run from the repository root:
```bash
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
Choose ACR or Docker Hub, supply a tag (default `latest`). The tag is sanitized (lowercase, hyphenated).

## Deploy to AKS
```bash
./scripts/deploy-image.sh      # Linux/macOS
scripts\deploy-image.bat       # Windows
```
The script prompts for resource group, cluster name, image URI and optional `WEATHER_API_KEY`, substitutes
`{{IMAGE_URI}}` / `{{WEATHER_API_KEY}}` in a temporary copy of the manifests, fetches credentials with
`az aks get-credentials`, and applies: namespace -> deployment -> service -> ingress, then waits for the rollout.

### Manifests (`kubernetes/`)
| File | Purpose |
|------|---------|
| namespace.yaml | `modresorts` namespace |
| deployment.yaml | 2 replicas, requests 250m/512Mi, limits 500m/1Gi, HTTP probes on `/health:8080` |
| service.yaml | ClusterIP, port 80 -> 8080 |
| ingress.yaml | AGIC ingress, host `modresorts.example.com` (change to your domain) |

## Troubleshooting
- Pod `ImagePullBackOff`: verify image URI and that ACR is attached to AKS.
- Pod `CrashLoopBackOff`: `kubectl logs <pod> -n modresorts`; check memory limit vs. `JAVA_OPTS`.
- Readiness failures: `kubectl describe pod`; increase `initialDelaySeconds`.
- Service issues: `kubectl get endpoints modresorts-service -n modresorts`; `kubectl port-forward svc/modresorts-service 8080:80 -n modresorts`.
- Ingress has no address: `kubectl describe ingress modresorts-ingress -n modresorts`; confirm AGIC add-on is enabled.

## Scaling and management
```bash
kubectl scale deployment/modresorts --replicas=4 -n modresorts
kubectl autoscale deployment/modresorts --cpu-percent=70 --min=2 --max=6 -n modresorts
kubectl set image deployment/modresorts modresorts=<new-image> -n modresorts
kubectl rollout undo deployment/modresorts -n modresorts
```

## Configuration
Set environment variables in `kubernetes/deployment.yaml`. Use a Kubernetes Secret (or Azure Key Vault CSI driver) for
`WEATHER_API_KEY` in production rather than a plain value.

## Security
- Container runs as non-root user `appuser`; no package installs or HEALTHCHECK in image
- Known-vulnerable dependencies in `pom.xml` (log4j-core 2.14.1, commons-collections 3.2.1) should be upgraded
- Enable TLS on the ingress and restrict namespace network access with NetworkPolicies

## Java notes
- Runtime image `eclipse-temurin:8-jdk-alpine` (explicit base image); JVM flags via `JAVA_OPTS`
  (`-Xms256m -Xmx512m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0`). Note: with `-Xmx` set, MaxRAMPercentage is ignored.
- `TZ=UTC`, UTF-8 encoding
