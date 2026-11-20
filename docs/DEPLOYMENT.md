# ModResorts – Deployment Guide (Docker and AWS EKS)

## 1. Overview
ModResorts is a Spring Boot 2.7 (Java 8, Maven) application packaged as an executable JAR with embedded Tomcat. It listens on port **8080** (Spring default; no `server.port` configured) and exposes a health endpoint at **`/health`** (`HealthServlet`, returns `{"status":"UP"}`). Spring Boot Actuator is not used.

Runtime base image: `eclipse-temurin:8-jre`. Builder: `maven:3.9.4-eclipse-temurin-8`.

## 2. Prerequisites
- Docker 20.10+
- AWS CLI v2, configured (`aws configure`)
- kubectl matching your cluster version
- eksctl (optional, to create a cluster)
- An EKS cluster with the AWS Load Balancer Controller installed (needed for the ALB Ingress)
- IAM permissions: `ecr:*` (push), `eks:DescribeCluster`, and cluster access mapped in `aws-auth`/access entries

## 3. Local development with Docker Compose
```bash
export WEATHER_API_KEY=your-key   # optional
docker compose up --build
```
Open http://localhost:8080/ and check http://localhost:8080/health.

## 4. Build and push the image
From the repository root:
```bash
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
Choose AWS ECR or Docker Hub, enter an optional tag (default `latest`; names are lowercased and sanitized). For ECR the repository is created automatically if missing. The script prints the final image URI.

## 5. EKS cluster setup
```bash
eksctl create cluster --name modresorts-cluster --region us-east-1 --nodes 2
aws eks update-kubeconfig --region us-east-1 --name modresorts-cluster
kubectl get nodes
```
Install the AWS Load Balancer Controller (see AWS docs) so `kubernetes.io/ingress.class: alb` is honoured.

## 6. Deploy to EKS
```bash
./scripts/deploy-image.sh      # Linux/macOS
scripts\deploy-image.bat       # Windows
```
The script prompts for region, cluster, image URI and optional environment variables, substitutes placeholders in a temporary copy of `kubernetes/*.yaml`, applies namespace → deployment → service → ingress, waits for the rollout and prints the ALB hostname.

### Manifests
| File | Purpose |
|------|---------|
| `kubernetes/namespace.yaml` | `modresorts` namespace |
| `kubernetes/deployment.yaml` | 2 replicas, probes on `/health:8080`, requests 250m/512Mi, limits 500m/1Gi |
| `kubernetes/service.yaml` | ClusterIP, port 80 → 8080 |
| `kubernetes/ingress.yaml` | ALB internet-facing ingress, health check `/health` |

Placeholders: `{{IMAGE_URI}}`, `{{WEATHER_API_KEY}}`, `{{SERVER_NAME}}`, `{{JNDI_INITIAL_CONTEXT_FACTORY}}`, `{{JNDI_PROVIDER_URL}}`.

## 7. Configuration
| Variable | Purpose |
|----------|---------|
| `WEATHER_API_KEY` | Weather service key used by `WeatherServlet` (fallback data is used if unset) |
| `SERVER_NAME` | Server identity shown by the app (defaults to `HOSTNAME`) |
| `JNDI_INITIAL_CONTEXT_FACTORY` / `JNDI_PROVIDER_URL` | Optional remote naming provider |
| `JAVA_OPTS` | JVM flags (default `-XX:MaxRAMPercentage=75.0`) |
| `SPRING_PROFILES_ACTIVE` | `docker` |
| `TZ` | `UTC` |

For sensitive values such as `WEATHER_API_KEY`, prefer a Kubernetes Secret (or AWS Secrets Manager via External Secrets) over plain env values.

The application also bundles the SQL Server JDBC driver; if a database is used, supply connection settings through additional environment variables.

## 8. Scaling and management
```bash
kubectl scale deployment/modresorts -n modresorts --replicas=4
kubectl autoscale deployment modresorts -n modresorts --cpu-percent=70 --min=2 --max=6
kubectl set image deployment/modresorts modresorts=<new-image> -n modresorts
kubectl rollout status deployment/modresorts -n modresorts
kubectl rollout undo deployment/modresorts -n modresorts
```
HPA requires metrics-server.

## 9. Troubleshooting
- **Pods in ImagePullBackOff**: check the image URI and that node role has `AmazonEC2ContainerRegistryReadOnly`.
- **CrashLoopBackOff / probe failures**: `kubectl logs <pod> -n modresorts`, `kubectl describe pod ...`. JVM startup may need longer `initialDelaySeconds`.
- **OOMKilled**: raise the memory limit; heap is 75% of the container limit.
- **Service has no endpoints**: `kubectl get endpoints -n modresorts`; verify selector `app: modresorts` and readiness.
- **Ingress has no address**: confirm the AWS Load Balancer Controller is running (`kubectl get pods -n kube-system`) and subnets are tagged for ELB.
- **ALB targets unhealthy**: health check path must be `/health` returning 200.

## 10. Security
- Container runs as non-root user `app`.
- Do not bake secrets into the image; use Secrets.
- Wrapper scripts (mvnw/gradlew) are excluded from the build context.
- Dependencies in `pom.xml` include old versions (log4j-core 2.14.1, jackson-databind 2.9.10, commons-collections 3.2.1) with known CVEs — upgrade before production.
- Add TLS on the ALB (ACM certificate, `alb.ingress.kubernetes.io/certificate-arn`).

## 11. Java notes
- JVM uses container-aware memory settings (`-XX:MaxRAMPercentage=75.0`).
- The JVM is started with `exec` so SIGTERM triggers Spring's graceful shutdown.
- No HEALTHCHECK in the Dockerfile; Kubernetes probes handle health.
