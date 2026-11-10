# ModResorts - Azure AKS Deployment Guide

## Application summary
- Java 8 Maven WAR (`modresorts-2.0.0.war`), Servlet 3.1 / Java EE 7 APIs (provided by the container)
- Runtime image: `eclipse-temurin:8-jdk` with Apache Tomcat 9 (copied from `tomcat:9.0-jdk8-temurin`); WAR deployed as `ROOT.war`
- Port: 8080. Health endpoint: `GET /health` (returns `{"status":"UP"}`)
- Environment variables: `WEATHER_API_KEY` (weather service key), `SERVER_NAME` (optional display name; falls back to `HOSTNAME`)
- Customer DB access is disabled in code (JNDI lookup commented out); no database container is required.

## Prerequisites
- Docker 20+, Azure CLI, kubectl, Azure subscription, an AKS cluster with Application Gateway Ingress Controller (AGIC), and an ACR (or Docker Hub account)

## Local development
```bash
export WEATHER_API_KEY=your-key
docker compose up --build
# http://localhost:8080/  and  http://localhost:8080/health
```

## Build and push
Run from the repository root:
```bash
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
Choose ACR or Docker Hub; the tag is sanitized (lowercase, hyphenated, defaults to `latest`).

## AKS setup
```bash
az login
az aks get-credentials --resource-group <rg> --name <cluster>
az aks update -g <rg> -n <cluster> --attach-acr <acr-name>   # allow pulls from ACR
```

## Deploy
```bash
./scripts/deploy-image.sh      # or scripts\deploy-image.bat
```
The script prompts for resource group, cluster, image URI and env values, substitutes `{{IMAGE_URI}}`, `{{NAMESPACE}}`, `{{WEATHER_API_KEY}}`, `{{SERVER_NAME}}` in a temporary copy of the manifests, then applies namespace -> deployment -> service -> ingress and waits for the rollout.

Manifests (`kubernetes/`): `namespace.yaml` (modresorts), `deployment.yaml` (2 replicas, 250m/512Mi requests, 500m/1Gi limits, HTTP probes on `/health`), `service.yaml` (ClusterIP 80 -> 8080), `ingress.yaml` (AGIC, host `modresorts.example.com` - change to your domain).

## Operations
```bash
kubectl get pods,svc,ingress -n modresorts
kubectl logs deploy/modresorts -n modresorts
kubectl scale deploy/modresorts -n modresorts --replicas=4
kubectl autoscale deploy/modresorts -n modresorts --cpu-percent=70 --min=2 --max=6
kubectl rollout undo deploy/modresorts -n modresorts
```

## Troubleshooting
- `ImagePullBackOff`: ACR not attached to AKS or wrong image URI/tag.
- `CrashLoopBackOff`: check `kubectl logs`; verify memory limit (JVM uses 75% of container memory).
- Probe failures: Tomcat start takes 20-40s; increase `initialDelaySeconds`. Verify `/health` with `kubectl port-forward`.
- Ingress has no address: confirm AGIC is installed (`kubectl get pods -n kube-system | grep ingress`).
- 404 at `/`: confirm WAR is deployed as ROOT (`kubectl exec ... ls /opt/tomcat/webapps`).

## Security
- Container runs as non-root user (uid 1001); store `WEATHER_API_KEY` in a Kubernetes Secret / Azure Key Vault for production instead of plain env values.
- Dependencies in `pom.xml` are outdated (log4j-core 2.14.1 - Log4Shell, jackson-databind 2.9.10, commons-collections 3.2.1, Spring 5.3.17); upgrade them.
- Enable TLS on the Application Gateway listener.
