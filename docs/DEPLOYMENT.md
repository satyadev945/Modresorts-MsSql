# ModResorts – Deployment Guide (AWS EKS)

## Application summary
- Spring Boot 2.7.18, Java 8, Maven, executable WAR (`target/modresorts-2.0.0.war`, embedded Tomcat)
- Port: 8080 (Spring Boot default, no override in config)
- Health endpoint: `GET /health` (`HealthServlet`, returns `{"status":"UP"}`); no Actuator dependency
- Optional env vars: `WEATHER_SERVICE_URL`, `WEATHER_API_KEY` (mock data is used when both are empty), `SERVER_NAME`, `SERVER_FULL_NAME`, `JNDI_INITIAL_CONTEXT_FACTORY`, `JNDI_PROVIDER_URL`
- Runtime image: `eclipse-temurin:8-jre` (explicit base image)

## Prerequisites
Docker 20+, AWS CLI v2 (configured), kubectl, eksctl (optional), an EKS cluster with the AWS Load Balancer Controller installed, and IAM permissions for ECR (`ecr:*` push/create), `eks:DescribeCluster`, and Kubernetes RBAC to create namespaces/deployments.

## Local development
```
docker compose up --build
curl http://localhost:8080/health
```
Set `WEATHER_SERVICE_URL` / `WEATHER_API_KEY` in your shell or a `.env` file if needed.

## Build and push
Run from the repository root:
```
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
Choose AWS ECR or Docker Hub; the tag is sanitized (lowercase, hyphenated, default `latest`). The ECR repository is created automatically if missing.

## Deploy to EKS
```
./scripts/deploy-image.sh      # Linux/macOS
scripts\deploy-image.bat       # Windows
```
The script prompts for region, cluster, image URI and optional env vars, runs `aws eks update-kubeconfig`, applies manifests in order (namespace, deployment, service, ingress) from a temporary copy with placeholders (`{{IMAGE_URI}}`, `{{WEATHER_SERVICE_URL}}`, `{{WEATHER_API_KEY}}`) substituted, then waits for rollout.

Manifests (`kubernetes/`):
- `namespace.yaml` – namespace `modresorts`
- `deployment.yaml` – 2 replicas, requests 250m/512Mi, limits 500m/1Gi, liveness/readiness on `/health:8080`
- `service.yaml` – ClusterIP 80 -> 8080
- `ingress.yaml` – ALB (internet-facing, ip target type); host `modresorts.example.com` – edit to your domain or remove the `host` line to accept any host.

## Scaling and management
```
kubectl scale deployment/modresorts -n modresorts --replicas=4
kubectl autoscale deployment modresorts -n modresorts --cpu-percent=70 --min=2 --max=6   # requires metrics-server
kubectl set image deployment/modresorts modresorts=<new-image> -n modresorts
kubectl rollout undo deployment/modresorts -n modresorts
```

## Troubleshooting
- Pods `CrashLoopBackOff`: `kubectl logs -l app=modresorts -n modresorts`; check memory limits vs JVM (`MaxRAMPercentage=75`).
- `ImagePullBackOff`: verify image URI and that node role has ECR read access.
- Probe failures: Java startup can take ~30–60s; increase `initialDelaySeconds`.
- Ingress has no address: confirm the AWS Load Balancer Controller is running (`kubectl get pods -n kube-system`) and subnets are tagged properly.
- Service check: `kubectl port-forward svc/modresorts-service 8080:80 -n modresorts`.

## Security notes
- Container runs as non-root user `appuser`.
- Store `WEATHER_API_KEY` in a Kubernetes Secret (or AWS Secrets Manager) for production rather than a plain env value.
- Enable HTTPS on the ALB with an ACM certificate (`alb.ingress.kubernetes.io/certificate-arn`).
- Known vulnerable pinned dependencies in `pom.xml` (log4j-core 2.14.1, jackson-databind 2.9.10, commons-collections 3.2.1) should be upgraded before production use.
- The app writes `reservations.zip` to the user home (`/home/appuser`); this is ephemeral in pods.
