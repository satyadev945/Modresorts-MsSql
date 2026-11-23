# ModResorts – Deployment Guide (AWS EKS)

## 1. Application overview
- Spring Boot 2.7.18 (Java 8), Maven, packaged as an executable WAR (`target/modresorts-2.0.0.war`, run with `java -jar`).
- Port: 8080 (Spring Boot default; no `server.port` override).
- Health endpoint: `GET /health` (`HealthServlet`, returns `{"status":"UP"}`). Spring Actuator is not a dependency.
- Environment variables read by the app: `WEATHER_API_KEY`, `ENABLE_JMX_MBEAN`, `SERVER_NAME`, `HOSTNAME`.
- Runtime base image: `eclipse-temurin:8-jdk-alpine` (explicitly requested).

## 2. Prerequisites
Docker 20+, AWS CLI v2 (configured), kubectl, eksctl (optional), an EKS cluster with the AWS Load Balancer Controller installed, and IAM permissions for ECR (`ecr:*` push/create) and `eks:DescribeCluster`.

## 3. Local development
```bash
docker compose up --build
curl http://localhost:8080/health
```
Optional: `WEATHER_API_KEY=xxx ENABLE_JMX_MBEAN=false docker compose up`.

## 4. Build and push
Run from the repository root:
```bash
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
Choose AWS ECR or Docker Hub, supply the tag (default `latest`). ECR repositories are created automatically. Note the printed image URI.

## 5. EKS setup
```bash
eksctl create cluster --name modresorts-cluster --region us-east-1 --nodes 2
aws eks update-kubeconfig --region us-east-1 --name modresorts-cluster
kubectl cluster-info
```
Install the AWS Load Balancer Controller (required for the ALB ingress).

## 6. Deploy
```bash
./scripts/deploy-image.sh      # or scripts\deploy-image.bat
```
The script prompts for region, cluster, image URI and optional env vars, substitutes `{{IMAGE_URI}}`, `{{WEATHER_API_KEY}}`, `{{ENABLE_JMX_MBEAN}}` into a temporary copy of the manifests, then applies namespace → deployment → service → ingress and waits for rollout.

Manifests (`kubernetes/`):
- `namespace.yaml` – namespace `modresorts`
- `deployment.yaml` – 2 replicas, requests 250m/512Mi, limits 500m/1Gi, HTTP probes on `/health`
- `service.yaml` – ClusterIP, 80 → 8080
- `ingress.yaml` – ALB internet-facing ingress

Get the URL: `kubectl get ingress modresorts-ingress -n modresorts`.

## 7. Operations
```bash
kubectl scale deployment/modresorts -n modresorts --replicas=3
kubectl autoscale deployment modresorts -n modresorts --cpu-percent=70 --min=2 --max=6   # HPA (needs metrics-server)
kubectl set image deployment/modresorts modresorts=<new-image> -n modresorts
kubectl rollout status deployment/modresorts -n modresorts
kubectl rollout undo deployment/modresorts -n modresorts
```

## 8. Troubleshooting
- Pods `ImagePullBackOff`: check ECR permissions on the node role and the image URI/tag.
- `CrashLoopBackOff`: `kubectl logs -l app=modresorts -n modresorts --previous`; check memory limits (JVM uses 75% of container RAM).
- Probe failures: JVM start can take 30–60 s; raise `initialDelaySeconds`.
- Service unreachable: `kubectl get endpoints modresorts-service -n modresorts`.
- Ingress has no address: verify the AWS Load Balancer Controller logs and subnet tags.

## 9. Configuration and security
- Pass secrets (e.g. `WEATHER_API_KEY`) via Kubernetes Secrets in production rather than plain env values.
- Container runs as non-root user `appuser`; no HEALTHCHECK in the image (Kubernetes probes are used).
- The project depends on outdated libraries (log4j-core 2.14.1, jackson-databind 2.9.10, commons-collections 3.2.1) with known CVEs — upgrade them.
- Add TLS to the ingress using an ACM certificate (`alb.ingress.kubernetes.io/certificate-arn`).
- The app uses SQL Server (`mssql-jdbc`); supply connection details externally if the DB code path is enabled.
