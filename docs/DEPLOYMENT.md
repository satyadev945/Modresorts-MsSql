# ModResorts – Deployment Guide (Docker & AWS EKS)

## Application overview
- Java 8, Maven, **WAR** packaging (`modresorts-2.0.0.war`), Java EE 7 / Servlet 3.1 (`javax.*`).
- Runs on Apache Tomcat 9 inside the container (Tomcat is copied from the official `tomcat:9.0-jdk8-temurin` image into the runtime base `eclipse-temurin:8-jdk`).
- Port: **8080**. Health endpoint: **`/health`** (`HealthServlet`, returns `{"status":"UP"}`).
- Optional environment variables: `WEATHER_API_KEY` (WeatherServlet), `SERVER_NAME`.
- No database is required (the JNDI datasource is disabled in the code).

## Prerequisites
- Docker 20.10+ (with BuildKit), Docker Compose v2
- AWS CLI v2 configured (`aws configure`), `kubectl`, optionally `eksctl`
- IAM permissions: ECR (`ecr:*` for push/create repo), EKS (`eks:DescribeCluster`), and cluster access (aws-auth / access entry)
- An EKS cluster with the **AWS Load Balancer Controller** installed (needed for the ALB Ingress)

## Local development with Docker Compose
```bash
export WEATHER_API_KEY=your-key   # optional
docker compose up --build
curl http://localhost:8080/health
```
Open http://localhost:8080/ in a browser.

## Build and push the image
Run from the repository root:
```bash
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
You are prompted for an image tag (default `latest`) and a registry (1. AWS ECR – the repository is created automatically if missing, 2. Docker Hub).

## Deploy to EKS
```bash
./scripts/deploy-image.sh      # Linux/macOS
scripts\deploy-image.bat       # Windows
```
The script prompts for region, cluster name, image URI, and optional `WEATHER_API_KEY` / `SERVER_NAME`. It substitutes the `{{...}}` placeholders in a temporary copy of `kubernetes/`, runs `aws eks update-kubeconfig`, applies manifests in order (namespace → deployment → service → ingress), waits for the rollout and prints resources.

### Manifests
| File | Purpose |
|------|---------|
| `kubernetes/namespace.yaml` | Namespace `modresorts` |
| `kubernetes/deployment.yaml` | 2 replicas, requests 250m/512Mi, limits 500m/1Gi, startup/liveness/readiness probes on `/health:8080` |
| `kubernetes/service.yaml` | ClusterIP, port 80 → 8080 |
| `kubernetes/ingress.yaml` | ALB ingress (internet-facing, target-type ip, health check `/health`). Change the host `modresorts.example.com` to your domain, or remove the `host` to match any host |

## Scaling and management
```bash
kubectl scale deployment/modresorts -n modresorts --replicas=4
kubectl autoscale deployment/modresorts -n modresorts --cpu-percent=70 --min=2 --max=6   # needs metrics-server
kubectl set image deployment/modresorts modresorts=<new-image> -n modresorts
kubectl rollout status deployment/modresorts -n modresorts
kubectl rollout undo deployment/modresorts -n modresorts
```

## Troubleshooting
- **Pods in `ImagePullBackOff`**: verify the image URI and that the node role has `AmazonEC2ContainerRegistryReadOnly`.
- **Pods `CrashLoopBackOff` / not ready**: `kubectl logs -l app=modresorts -n modresorts`; `kubectl describe pod`. Tomcat takes ~20-40 s to start; the startup probe allows 150 s.
- **OOMKilled**: raise the memory limit; the JVM uses `MaxRAMPercentage=75`.
- **Service unreachable**: `kubectl get endpoints -n modresorts`; check selector `app=modresorts`.
- **Ingress has no address**: confirm the AWS Load Balancer Controller is running (`kubectl get pods -n kube-system`) and subnets are tagged for ELB.
- **`kubectl` unauthorized**: ensure your IAM identity is mapped in the cluster (access entries or `aws-auth`).

## Configuration management
Environment variables are set in `kubernetes/deployment.yaml`. For secrets such as `WEATHER_API_KEY`, prefer a Kubernetes Secret (or AWS Secrets Manager with the CSI driver) and reference it via `valueFrom.secretKeyRef`.

## Security considerations
- Container runs as non-root user `appuser`; no package managers or extra tools are installed in the runtime image.
- Terminate TLS at the ALB (add an ACM certificate annotation and 443 listener).
- Dependencies in `pom.xml` include old versions (e.g. log4j-core 2.14.1, jackson-databind 2.9.10); upgrade them before production use.
- Wrapper scripts (mvnw/gradlew) are excluded from the build context; builds use the system `mvn`.

## Java notes
- JVM flags are provided via `JAVA_OPTS` (container-aware memory, UTC timezone, UTF-8).
- The Dockerfile has no `HEALTHCHECK`; Kubernetes probes handle health checking.
- The runtime base image is `eclipse-temurin:8-jdk` (explicitly requested); a JRE-only image would give a smaller footprint.
