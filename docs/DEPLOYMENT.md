# ModResorts – Deployment Guide (Docker & AWS EKS)

## 1. Overview
ModResorts is a Java 8 / Maven WAR application (Java EE 7 servlets, `javax.servlet`) packaged into a container running on Apache Tomcat 9 with an `eclipse-temurin:8-jre` runtime base image.

- Port: **8080**
- Health endpoint: **`/health`** (`HealthServlet`, returns `{"status":"UP"}`)
- External dependencies (provided separately): Redis (`REDIS_HOST`, `REDIS_PORT`, `REDIS_CACHE_TTL`), weather API key (`WEATHER_API_KEY` or `WEATHER_API_KEY_FILE`)

## 2. Prerequisites
- Docker 20.10+
- AWS CLI v2 configured (`aws configure`) with ECR and EKS permissions
- kubectl compatible with your cluster version
- eksctl (optional, for cluster creation)
- An EKS cluster with the **AWS Load Balancer Controller** installed (required for the ALB ingress)

## 3. Local development with Docker Compose
```bash
export REDIS_HOST=host.docker.internal   # optional
docker compose up --build
curl http://localhost:8080/health
```
Only the application is defined; Redis and other services must be provided externally.

## 4. Build and push the image
Run from the repository root:
```bash
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
The script asks for the registry (1. AWS ECR, 2. Docker Hub), tag (default `latest`), sanitizes names, creates the ECR repository if needed, builds with `docker build -f Dockerfile -t <image> .` and pushes.

The Dockerfile is multi-stage: PurgeCSS (node) → Maven build (`maven:3.9.4-eclipse-temurin-8`) → Tomcat 9 (copied into) → runtime `eclipse-temurin:8-jre`. It runs as non-root user `appuser` (uid 1001).

## 5. EKS setup
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
The script prompts for region, cluster, image URI and optional env values, renders `kubernetes/*.yaml` placeholders into a temp directory, and applies them in order: namespace → deployment → service → ingress. It then waits for rollout and prints the ALB hostname.

| Manifest | Description |
|---|---|
| `namespace.yaml` | `modresorts` namespace |
| `deployment.yaml` | 2 replicas, requests 250m/512Mi, limits 500m/1Gi, HTTP probes on `/health:8080` |
| `service.yaml` | ClusterIP, 80 → 8080 |
| `ingress.yaml` | ALB internet-facing ingress, host `modresorts.example.com` (edit the host or remove it to use the ALB DNS directly) |

## 7. Configuration
| Variable | Default | Purpose |
|---|---|---|
| `REDIS_HOST` | localhost | Redis cache host |
| `REDIS_PORT` | 6379 | Redis port |
| `REDIS_CACHE_TTL` | 300 | Cache TTL (seconds) |
| `WEATHER_API_KEY` | – | Weather API key |
| `WEATHER_API_KEY_FILE` | – | Path to a mounted file containing the key |
| `CATALINA_OPTS` | `-Xms256m -Xmx512m ...` | JVM options |
| `TZ` | UTC | Timezone |

For production, store `WEATHER_API_KEY` in a Kubernetes Secret (or AWS Secrets Manager) and reference it with `secretKeyRef` instead of a plain env value.

## 8. Scaling and management
```bash
kubectl scale deployment/modresorts -n modresorts --replicas=4
kubectl autoscale deployment modresorts -n modresorts --cpu-percent=70 --min=2 --max=6   # needs metrics-server
kubectl set image deployment/modresorts modresorts=<new-image> -n modresorts
kubectl rollout status deployment/modresorts -n modresorts
kubectl rollout undo deployment/modresorts -n modresorts
```

## 9. Troubleshooting
- **ImagePullBackOff**: verify image URI; ensure node role has `AmazonEC2ContainerRegistryReadOnly`.
- **CrashLoopBackOff / probe failures**: `kubectl logs -l app=modresorts -n modresorts`; `kubectl describe pod ...`. Startup probe allows up to ~150s.
- **OOMKilled**: raise memory limit and adjust `-Xmx` / `MaxRAMPercentage`.
- **Service has no endpoints**: `kubectl get endpoints -n modresorts`; check label `app=modresorts`.
- **Ingress has no ADDRESS**: confirm AWS Load Balancer Controller is running (`kubectl get pods -n kube-system`), subnets are tagged for ELB, check `kubectl describe ingress -n modresorts`.
- **Redis errors**: verify `REDIS_HOST` is reachable from the pods (security groups).

## 10. Security considerations
- Container runs as non-root; no package managers or extra tools are installed in the runtime image.
- Dependencies in `pom.xml` include outdated libraries (e.g. log4j-core 2.14.1, jackson-databind 2.9.10, commons-collections 3.2.1, Spring 5.3.17) with known vulnerabilities – upgrade them before production use.
- `SSLUtils`/`FakeX509TrustManager` disable certificate validation; review before exposing externally.
- Add TLS to the ALB (ACM certificate + `alb.ingress.kubernetes.io/certificate-arn`, listen-ports 443).
- Do not commit secrets; use Kubernetes Secrets / IRSA.

## 11. Java-specific notes
- Java 8: `-XX:MaxRAMPercentage` and container support require 8u191+ (provided by the temurin image).
- The WAR is deployed as `ROOT.war`, so the app is served at `/`.
- Tomcat runs in the foreground via `catalina.sh run`, so SIGTERM triggers graceful shutdown.
- Wrapper scripts (`gradlew`, `mvnw`) are excluded; the build uses the system `mvn`.
