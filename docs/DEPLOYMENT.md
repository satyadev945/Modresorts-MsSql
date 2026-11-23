# ModResorts – Deployment Guide (AWS EKS)

## 1. Application overview
| Item | Value |
|------|-------|
| Type | Java EE 7 web application (WAR, `modresorts-2.0.0.war`), servlets/filters, no Spring Boot |
| Build | Maven (`mvn clean package -DskipTests`), Java 8 |
| Runtime | Apache Tomcat 9 (javax.* namespace) on `eclipse-temurin:8-jdk-alpine` |
| Port | 8080 (deployed as ROOT context) |
| Health | `GET /health` → `{"status":"UP"}` (`HealthServlet`) |
| Env vars | `WEATHER_SERVICE_URL`, `WEATHER_API_KEY`, `SERVER_NAME`, `JNDI_INITIAL_CONTEXT_FACTORY`, `JNDI_PROVIDER_URL` (all optional) |

## 2. Prerequisites
- Docker 20.10+
- AWS CLI v2 configured (`aws configure`) with ECR and EKS permissions
- kubectl, (optional) eksctl
- An EKS cluster with the **AWS Load Balancer Controller** installed (needed for the ALB Ingress)

## 3. Local development (Docker Compose)
```bash
docker compose up --build
curl http://localhost:8080/health
```
Optional settings can be exported before running, e.g. `WEATHER_API_KEY=xxxx docker compose up --build`.

## 4. Build and push the image
Run from the project root:
```bash
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
The script prompts for the tag (default `latest`), registry (1 = AWS ECR, 2 = Docker Hub) and credentials. For ECR the repository is created automatically if missing. Note the printed image URI.

The Dockerfile stages: (1) PurgeCSS, (2) Maven build, (3) Tomcat distribution, (4) runtime on `eclipse-temurin:8-jdk-alpine` running as non-root user `appuser` (UID 1001).

## 5. EKS setup
```bash
eksctl create cluster --name my-cluster --region us-east-1 --nodes 2   # if you have none
aws eks update-kubeconfig --region us-east-1 --name my-cluster
kubectl cluster-info
```
Install the AWS Load Balancer Controller per the AWS documentation (IAM OIDC provider, IAM policy, Helm chart).

## 6. Deploy
```bash
./scripts/deploy-image.sh      # Linux/macOS
scripts\deploy-image.bat       # Windows
```
The script prompts for region, cluster, image URI and the optional env vars, substitutes placeholders (`{{IMAGE_URI}}`, `{{WEATHER_SERVICE_URL}}`, …) in a temporary copy of the manifests (your files stay untouched), applies them in order, waits for rollout and prints the ALB hostname.

### Manifests (`kubernetes/`)
| File | Purpose |
|------|---------|
| `namespace.yaml` | Namespace `modresorts` |
| `deployment.yaml` | 2 replicas, requests 250m/512Mi, limits 500m/1Gi, HTTP probes on `/health` |
| `service.yaml` | ClusterIP, port 80 → 8080 |
| `ingress.yaml` | ALB internet-facing ingress, health check `/health` |

## 7. Troubleshooting
- **Pods in `CrashLoopBackOff`**: `kubectl logs deploy/modresorts -n modresorts`; check heap vs. memory limit (`MaxRAMPercentage=75`).
- **`ImagePullBackOff`**: verify the image URI and that the node role has `AmazonEC2ContainerRegistryReadOnly` (ECR) or add an imagePullSecret (private Docker Hub).
- **Readiness failing**: `kubectl exec` into the pod and call `wget -qO- localhost:8080/health`; increase `initialDelaySeconds` for slow nodes.
- **Ingress has no address**: confirm controller pods (`kubectl get pods -n kube-system | grep load-balancer`), subnet tags, and `kubectl describe ingress -n modresorts`.
- **Service unreachable**: `kubectl get endpoints modresorts-service -n modresorts` must list pod IPs.

## 8. Scaling and management
```bash
kubectl scale deployment/modresorts -n modresorts --replicas=4
kubectl autoscale deployment modresorts -n modresorts --cpu-percent=70 --min=2 --max=6   # needs metrics-server
kubectl set image deployment/modresorts modresorts=<new-image-uri> -n modresorts
kubectl rollout status deployment/modresorts -n modresorts
kubectl rollout undo deployment/modresorts -n modresorts
```

## 9. Configuration management
Environment variables are set in `deployment.yaml`. `WEATHER_API_KEY` is sensitive: for production move it to a Kubernetes Secret (or AWS Secrets Manager via the CSI driver) and reference it with `valueFrom.secretKeyRef`. When `WEATHER_SERVICE_URL` is set, weather requests are delegated to that service; otherwise `WEATHER_API_KEY` enables live data, else bundled sample data is used.

## 10. Security considerations
- Container runs as non-root; no extra packages installed in the runtime stage.
- Use ECR image scanning and immutable tags in production; pin versions rather than `latest`.
- Add TLS to the ingress (ACM certificate annotation `alb.ingress.kubernetes.io/certificate-arn`, listen-ports 443).
- Dependencies in `pom.xml` include outdated libraries (e.g. log4j-core 2.14.1, jackson-databind 2.9.10, commons-collections 3.2.1, spring 5.3.x) with known CVEs – upgrade before production use.
- `FakeX509TrustManager`/`SSLUtils` in the source disable certificate validation; review before exposing to the internet.
- Restrict access with security groups / WAF, and apply NetworkPolicies.

## 11. Java-specific notes
- The WAR targets Servlet 3.1 / javax.*, hence Tomcat 9 (not 10+).
- JVM flags via `JAVA_OPTS`: `-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Xms256m -Duser.timezone=UTC`.
- The explicit runtime base image `eclipse-temurin:8-jdk-alpine` does not ship a servlet container, so Tomcat is copied from `tomcat:9.0-jdk8-temurin` during the build.
- `catalina.sh run` runs in foreground and handles SIGTERM for graceful shutdown (grace period 30s).
- JMX/MBeans are registered in-JVM; to expose remotely add JMX options to `JAVA_OPTS`.
