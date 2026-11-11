# ModResorts – Deployment Guide (Docker & AWS EKS)

## 1. Overview
ModResorts is a Java 8 servlet application packaged as a WAR (`modresorts-2.0.0.war`, Maven, `javax.servlet`). In the container it runs as `ROOT.war` on Apache Tomcat 9 over the runtime base image `eclipse-temurin:8-jre`.

- Port: **8080** (Tomcat default; no application config overrides it)
- Health endpoint: **`/health`** (`HealthServlet`, returns `{"status":"UP"}`) – used by liveness and readiness probes
- Optional env var: `WEATHER_API_KEY` (if empty, bundled default weather data is used)
- The app writes `reservations.zip` to `user.home` (`/home/app` in the container)

The runtime image is `eclipse-temurin:8-jre`, which contains no servlet container, so the Dockerfile copies the Tomcat 9 distribution from `tomcat:9.0-jre8-temurin` into it. No package manager is run in the runtime stage and no HEALTHCHECK is baked in – Kubernetes probes handle health.

Dockerfile stages: (1) PurgeCSS (node) → (2) Maven build (`maven:3.9.4-eclipse-temurin-8`) → (3) Tomcat source → (4) runtime (`eclipse-temurin:8-jre`, non-root user `app`, uid 1001).

## 2. Prerequisites
- Docker 20.10+
- AWS CLI v2 configured (`aws configure` / SSO) with ECR and EKS permissions
- kubectl compatible with your cluster version
- An EKS cluster with the **AWS Load Balancer Controller** installed (needed for the ALB Ingress)
- (Optional) eksctl

IAM permissions: `ecr:*` for push (GetAuthorizationToken, CreateRepository, PutImage, etc.), `eks:DescribeCluster`, and a cluster access entry / aws-auth mapping granting your IAM identity access to the cluster.

## 3. Local development with Docker Compose
```bash
export WEATHER_API_KEY=   # optional
docker compose up --build
# open http://localhost:8080/ and http://localhost:8080/health
```
Compose defines only the application service; a named volume keeps `/home/app`.

## 4. Build and push the image
Run from the repository root.
```bash
chmod +x scripts/*.sh
./scripts/build-push.sh          # Linux/macOS
scripts\build-push.bat           # Windows
```
The script asks for the registry (1 = AWS ECR, 2 = Docker Hub), a tag (sanitized to lowercase, default `latest`), and registry details. For ECR it creates the repository if it does not exist. It prints the full image URI at the end.

## 5. Deploy to EKS
```bash
./scripts/deploy-image.sh        # Linux/macOS
scripts\deploy-image.bat         # Windows
```
The script prompts for AWS region, cluster name, image URI, namespace (default `modresorts`), ingress host and `WEATHER_API_KEY`. It substitutes `{{IMAGE_URI}}`, `{{NAMESPACE}}`, `{{INGRESS_HOST}}`, `{{WEATHER_API_KEY}}` in a temporary copy of `kubernetes/*.yaml`, runs `aws eks update-kubeconfig`, applies manifests in order (namespace → deployment → service → ingress), waits for rollout and prints resources.

### Manifests
| File | Purpose |
|---|---|
| `kubernetes/namespace.yaml` | Namespace |
| `kubernetes/deployment.yaml` | 2 replicas, requests 250m/512Mi, limits 500m/1Gi, probes on `/health:8080` |
| `kubernetes/service.yaml` | ClusterIP, port 80 → 8080 |
| `kubernetes/ingress.yaml` | ALB internet-facing ingress, target-type `ip`, health check `/health` |

Get the address: `kubectl get ingress modresorts-ingress -n modresorts`. Either send requests with the configured Host header or create a DNS CNAME to the ALB hostname.

## 6. Scaling and management
```bash
kubectl scale deployment/modresorts --replicas=4 -n modresorts
kubectl autoscale deployment modresorts --cpu-percent=70 --min=2 --max=6 -n modresorts   # needs metrics-server
kubectl set image deployment/modresorts modresorts=<new-image-uri> -n modresorts
kubectl rollout status deployment/modresorts -n modresorts
kubectl rollout undo deployment/modresorts -n modresorts
```
Rolling updates use maxUnavailable 0 / maxSurge 1.

## 7. Troubleshooting
- **Pods Pending**: `kubectl describe pod` – insufficient CPU/memory or no nodes.
- **ImagePullBackOff**: check image URI, and that node IAM role has `AmazonEC2ContainerRegistryReadOnly`.
- **CrashLoopBackOff / probe failures**: `kubectl logs deployment/modresorts -n modresorts`; Tomcat start can take 30–60 s on small CPUs – raise `initialDelaySeconds`. OOMKilled → raise the memory limit (JVM uses 75% of container memory).
- **Service has no endpoints**: `kubectl get endpoints -n modresorts`; check selector `app: modresorts` and readiness.
- **Ingress has no address**: confirm the AWS Load Balancer Controller is running (`kubectl get pods -n kube-system | grep load-balancer`), and subnets are tagged for ELB (`kubernetes.io/role/elb=1`). See `kubectl describe ingress`.
- **kubectl unauthorized**: re-run `aws eks update-kubeconfig` and verify cluster access entries.

## 8. Configuration
| Variable | Purpose |
|---|---|
| `WEATHER_API_KEY` | Optional real-time weather API key |
| `JAVA_OPTS` | JVM flags (`-XX:MaxRAMPercentage=75.0 -Xms256m` etc.) |
| `TZ` | Timezone (UTC) |

For production, store `WEATHER_API_KEY` in a Kubernetes Secret (or AWS Secrets Manager) and reference it with `secretKeyRef` instead of a plain value.

## 9. Security notes
- Container runs as non-root (uid 1001); no wrapper scripts or build tools in the runtime image.
- The sources include outdated dependencies (e.g. log4j-core 2.14.1, jackson-databind 2.9.10, commons-collections 3.2.1, spring 5.3.x) and a `FakeX509TrustManager`; upgrade/review before exposing publicly.
- Add TLS to the ALB (ACM certificate + `alb.ingress.kubernetes.io/certificate-arn`, `listen-ports` 443) for production.
- Application security constraints in `web.xml` are commented out for demo purposes.
- Scan images (ECR scan-on-push) and restrict ingress with `alb.ingress.kubernetes.io/inbound-cidrs` if needed.

## 10. Java notes
- `.dockerignore` excludes `mvnw`, `.mvn/`, `gradlew`, `gradle/wrapper/`; builds use system `mvn`.
- `javax.*` APIs: Tomcat 9 (not 10+) is required.
- Heap is container-aware (`-XX:+UseContainerSupport`, requires Java 8u191+, provided by the base image).
