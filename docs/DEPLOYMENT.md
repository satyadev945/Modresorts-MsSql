# ModResorts – Deployment Guide (Docker & AWS EKS)

## 1. Application overview
- Java EE 7 web application packaged as `modresorts-2.0.0.war` (Maven, Java 8, servlets/filters, no embedded server).
- Runs on Apache Tomcat 9 (bundled into the image) on top of the `eclipse-temurin:8-jre` runtime image.
- HTTP port: **8080**. Health endpoint: **`/health`** (`HealthServlet`, returns `{"status":"UP"}`).
- Optional external services (configured via environment variables): Redis cache, weather API, JNDI provider.

| Variable | Purpose | Default |
|---|---|---|
| `WEATHER_API_KEY` | Weather API key | empty |
| `REDIS_HOST` | Redis host (cache disabled if empty) | empty |
| `REDIS_PORT` | Redis port | 6379 |
| `REDIS_PASSWORD` | Redis password | empty |
| `REDIS_CACHE_TTL_SECONDS` | Cache TTL | 60 |
| `JNDI_INITIAL_CONTEXT_FACTORY` / `JNDI_PROVIDER_URL` | Optional JNDI settings | empty |
| `JAVA_OPTS` | JVM options | container-aware, `MaxRAMPercentage=75` |

## 2. Prerequisites
- Docker 20.10+ (BuildKit enabled), AWS CLI v2, kubectl, eksctl (optional)
- IAM permissions: ECR (`ecr:*` for push/create repo), EKS (`eks:DescribeCluster`) and cluster RBAC access
- An EKS cluster with the **AWS Load Balancer Controller** installed (needed by the Ingress)

## 3. Local development with Docker Compose
```bash
export WEATHER_API_KEY=...   # optional
export REDIS_HOST=host.docker.internal  # optional
docker compose up --build
curl http://localhost:8080/health
```
The compose file contains only the application service. Redis and other services must be provided externally.

## 4. Build and push the image
Run from the repository root:
```bash
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
The script asks for the registry (1. AWS ECR, 2. Docker Hub), the tag (sanitized to lowercase/hyphenated, default `latest`), authenticates, creates the ECR repository when missing, builds and pushes. The Dockerfile is multi-stage: PurgeCSS -> Maven build (`mvn clean package -DskipTests`) -> Tomcat preparation -> JRE runtime running as non-root user (UID 1001). No wrapper scripts (`mvnw`, `gradlew`) are used.

## 5. EKS cluster setup
```bash
eksctl create cluster --name modresorts-cluster --region us-east-1 --nodes 2
aws eks update-kubeconfig --region us-east-1 --name modresorts-cluster
kubectl cluster-info
```
Install the AWS Load Balancer Controller following the AWS documentation.

## 6. Deploy to EKS
```bash
./scripts/deploy-image.sh      # Linux/macOS
scripts\deploy-image.bat       # Windows
```
You are prompted for AWS region, cluster name, image URI, namespace (default `modresorts`) and optional environment values. Placeholders (`{{IMAGE_URI}}`, `{{NAMESPACE}}`, `{{REDIS_HOST}}`, ...) are replaced in a temporary copy of `kubernetes/*.yaml` (sed with `|` delimiter), then applied in order: namespace -> deployment -> service -> ingress. The script waits for the rollout and prints the ingress address.

### Manifests
- `namespace.yaml` – namespace.
- `deployment.yaml` – 2 replicas, rolling update, requests 250m/512Mi, limits 500m/1Gi, startup/liveness/readiness probes on `GET /health:8080`, non-root security context.
- `service.yaml` – ClusterIP, port 80 -> 8080.
- `ingress.yaml` – internet-facing ALB (`target-type: ip`, health check path `/health`).

## 7. Scaling and management
```bash
kubectl scale deployment/modresorts -n modresorts --replicas=4
kubectl autoscale deployment/modresorts -n modresorts --cpu-percent=70 --min=2 --max=6   # needs metrics-server
kubectl set image deployment/modresorts modresorts=<new-image-uri> -n modresorts
kubectl rollout status deployment/modresorts -n modresorts
kubectl rollout undo deployment/modresorts -n modresorts
```

## 8. Troubleshooting
- **Pods `ImagePullBackOff`**: verify image URI/tag; node IAM role needs `AmazonEC2ContainerRegistryReadOnly`.
- **Pods `CrashLoopBackOff`**: `kubectl logs deploy/modresorts -n modresorts`; check `kubectl describe pod`.
- **Readiness failing**: Tomcat startup takes ~15-30s; confirm `/health` with `kubectl port-forward svc/modresorts-service 8080:80 -n modresorts`.
- **OOMKilled**: raise memory limit; the JVM uses 75% of the container limit.
- **Ingress has no ADDRESS**: confirm the AWS Load Balancer Controller is running (`kubectl get pods -n kube-system`) and subnets are tagged for ELB.
- **Service unreachable**: `kubectl get endpoints -n modresorts`.

## 9. Security considerations
- Container runs as non-root (UID 1001); privilege escalation disabled; Tomcat shutdown port disabled.
- Environment values passed by the deploy script (including `REDIS_PASSWORD`) end up in the Deployment spec; for production move secrets to Kubernetes Secrets / AWS Secrets Manager.
- Enable HTTPS on the ALB with an ACM certificate (`alb.ingress.kubernetes.io/certificate-arn`).
- Several dependencies in `pom.xml` are outdated (e.g. log4j-core 2.14.1, jackson-databind 2.9.10, commons-collections 3.2.1); upgrade them before production use.
- Application security constraints in `web.xml` are commented out for demo purposes.

## 10. Java-specific notes
- Target runtime is Java 8; `-XX:MaxRAMPercentage` and container support require 8u191+ (provided by the temurin image).
- Tomcat 9 (javax.* namespace) is used; do not upgrade to Tomcat 10+ without migrating to `jakarta.*`.
- Timezone is UTC (`TZ`, `-Duser.timezone`). Logs go to stdout via `catalina.sh run`.
