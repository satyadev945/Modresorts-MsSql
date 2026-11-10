# ModResorts – Deployment Guide (Docker & AWS EKS)

## 1. Application overview
- Java 8, Maven, `war` packaging (`modresorts-2.0.0.war`), Java EE 7 / Servlet 3.1 application (originally Liberty/WebSphere).
- Runs in a container on Apache Tomcat 8.5 (copied from `tomcat:8.5-jre8-temurin`) on the runtime base image `eclipse-temurin:8-jre`. The WAR is deployed as `ROOT.war`, so the app is served at `/`.
- Port: **8080** (Tomcat default; no explicit configuration in the project).
- Health endpoint: `GET /health` (`HealthServlet`, returns `{"status":"UP"}`), used for Kubernetes probes and the ALB health check.
- Environment variables read by the code: `WEATHER_API_KEY` (optional; without it default weather data is served), `ENABLE_JMX_APPINFO` (optional, default `false`).
- No database is required at runtime (the JNDI datasource `jdbc/ModResortsJndi` is commented out).

## 2. Prerequisites
- Docker 20.10+ (with Compose v2)
- AWS CLI v2 configured (`aws configure`) with permissions for ECR and EKS
- kubectl matching your cluster version, and (optionally) eksctl
- An EKS cluster with the **AWS Load Balancer Controller** installed (required for the ALB Ingress)
- IAM permissions: `ecr:*` on the repository, `eks:DescribeCluster`, and a Kubernetes RBAC mapping for your IAM identity

## 3. Local development with Docker Compose
```bash
export WEATHER_API_KEY=   # optional
docker compose up --build
# open http://localhost:8080/  and  http://localhost:8080/health
docker compose down
```

## 4. Build and push the image
From the repository root:
```bash
./scripts/build-push.sh          # Linux/macOS
scripts\build-push.bat           # Windows
```
The script prompts for the tag (default `latest`; sanitized to lower case) and the registry (1. AWS ECR – the repository is created automatically if missing, 2. Docker Hub), then builds and pushes. Note the printed image URI.

## 5. EKS cluster setup
```bash
eksctl create cluster --name my-cluster --region us-east-1 --nodes 2      # if you need one
aws eks update-kubeconfig --region us-east-1 --name my-cluster
kubectl get nodes
```
Install the AWS Load Balancer Controller following the AWS documentation if it is not present.

## 6. Deploy to EKS
```bash
./scripts/deploy-image.sh        # Linux/macOS
scripts\deploy-image.bat         # Windows
```
You are prompted for region, cluster name, image URI, `WEATHER_API_KEY`, `ENABLE_JMX_APPINFO` and the ingress host. Placeholders (`{{IMAGE_URI}}`, `{{NAMESPACE}}`, `{{WEATHER_API_KEY}}`, `{{ENABLE_JMX_APPINFO}}`, `{{INGRESS_HOST}}`) are rendered into `.k8s-rendered/` (the originals are untouched) and applied in order: namespace → deployment → service → ingress.

### Manifests
| File | Purpose |
|------|---------|
| `kubernetes/namespace.yaml` | Namespace `modresorts` |
| `kubernetes/deployment.yaml` | 2 replicas, requests 250m/512Mi, limits 500m/1Gi, startup/liveness/readiness probes on `/health:8080`, runs as UID 1001 |
| `kubernetes/service.yaml` | ClusterIP, port 80 → 8080 |
| `kubernetes/ingress.yaml` | ALB (internet-facing, ip target type), health check `/health` |

Get the URL:
```bash
kubectl get ingress modresorts-ingress -n modresorts
```
If you use a custom host, create a DNS record pointing at the ALB; otherwise call the ALB with `curl -H "Host: <host>" http://<alb-dns>/`.

## 7. Scaling and management
```bash
kubectl scale deployment/modresorts -n modresorts --replicas=4
kubectl autoscale deployment modresorts -n modresorts --cpu-percent=70 --min=2 --max=6   # needs metrics-server
kubectl set image deployment/modresorts modresorts=<new-image-uri> -n modresorts           # rolling update
kubectl rollout status deployment/modresorts -n modresorts
kubectl rollout undo deployment/modresorts -n modresorts                                    # rollback
```

## 8. Troubleshooting
- **Pod in `ImagePullBackOff`**: verify the image URI and that the node IAM role has `AmazonEC2ContainerRegistryReadOnly`.
- **Pod `CrashLoopBackOff` / probes failing**: `kubectl logs -l app=modresorts -n modresorts`; `kubectl describe pod ...`. Startup takes ~20-40s; the startup probe allows 150s.
- **OOMKilled**: raise the memory limit; the JVM uses `MaxRAMPercentage=75`.
- **Service unreachable**: `kubectl get endpoints modresorts-service -n modresorts` must list pod IPs; check selector labels.
- **Ingress has no address**: confirm the AWS Load Balancer Controller is running (`kubectl get pods -n kube-system | grep load-balancer`) and subnets are tagged for ELB; `kubectl describe ingress -n modresorts`.
- **Build fails with log4j/dependency issues**: run `docker build --no-cache .` and check network access to Maven Central.

## 9. Configuration and security notes
- `WEATHER_API_KEY` is a secret; for production store it in a Kubernetes Secret (or AWS Secrets Manager) and reference it with `valueFrom.secretKeyRef` instead of a literal value.
- The container runs as non-root (UID 1001); no packages or extra tools are installed in the runtime image.
- The pom pins several old libraries (log4j-core 2.14.1, jackson-databind 2.9.10, commons-collections 3.2.1, spring 5.3.x) with known CVEs; upgrade them before production use.
- Use HTTPS on the ALB (ACM certificate annotations `alb.ingress.kubernetes.io/certificate-arn` and `listen-ports` with 443) for production.
- The application is the Java EE 7 app with form login configured but security constraints commented out in `web.xml`; add authentication before exposing it publicly.

## 10. Java-specific notes
- JVM flags are set through `JAVA_OPTS` (container support, `MaxRAMPercentage=75`, `-Xms256m`, UTC timezone, UTF-8).
- Wrapper scripts (mvnw/gradlew) are intentionally not used; the image builds with the system `mvn`.
- Tomcat handles SIGTERM via `catalina.sh run`, giving graceful shutdown within `terminationGracePeriodSeconds: 30`.
