# ModResorts – Deployment Guide (Docker & AWS EKS)

## 1. Application Summary
- Spring Boot 2.7.18 (Java 8), Maven, packaged as an executable WAR (`target/modresorts-2.0.0.war`) running on embedded Tomcat.
- Port: 8080 (Spring Boot default; no custom port configured).
- Health endpoint: `GET /health` (HealthServlet, returns `{"status":"UP"}`). Actuator is not used.
- Optional environment variables: `WEATHER_API_KEY`, `SERVER_NAME`.
- Runtime image: `eclipse-temurin:8-jdk-alpine`; non-root user `appuser`.

## 2. Prerequisites
Docker 20+, AWS CLI v2, kubectl, (optional) eksctl, an AWS account with IAM permissions for ECR (`ecr:*` on the repo) and EKS (`eks:DescribeCluster`), and an EKS cluster with the **AWS Load Balancer Controller** installed.

## 3. Local development (Docker Compose)
```bash
export WEATHER_API_KEY=your-key   # optional
docker compose up --build
curl http://localhost:8080/health
```
Only the application service is defined; external services are supplied through environment variables.

## 4. Build and push
From the repository root:
```bash
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
Choose AWS ECR or Docker Hub, enter the tag (default `latest`). For ECR the repository `modresorts` is created automatically. Note the printed image URI.

## 5. EKS setup
```bash
aws eks update-kubeconfig --region <region> --name <cluster>
kubectl cluster-info
```
Create a cluster if needed: `eksctl create cluster --name modresorts --region <region> --nodes 2`.

## 6. Deploy
```bash
./scripts/deploy-image.sh      # or scripts\deploy-image.bat
```
The script prompts for region, cluster, image URI and optional env vars, substitutes placeholders (`{{IMAGE_URI}}`, `{{WEATHER_API_KEY}}`, `{{SERVER_NAME}}`) in a temporary copy of the manifests, then applies them in order:
1. `kubernetes/namespace.yaml` – namespace `modresorts`
2. `kubernetes/deployment.yaml` – 2 replicas, requests 250m/512Mi, limits 500m/1Gi, startup/liveness/readiness probes on `/health:8080`
3. `kubernetes/service.yaml` – ClusterIP, port 80 → 8080
4. `kubernetes/ingress.yaml` – ALB (internet-facing, target-type ip, health check `/health`)

Verify: `kubectl get pods,svc,ingress -n modresorts`.

## 7. Scaling and management
```bash
kubectl scale deployment/modresorts -n modresorts --replicas=4
kubectl autoscale deployment modresorts -n modresorts --cpu-percent=70 --min=2 --max=6   # needs metrics-server
kubectl set image deployment/modresorts modresorts=<new-image> -n modresorts
kubectl rollout status deployment/modresorts -n modresorts
kubectl rollout undo deployment/modresorts -n modresorts
```

## 8. Troubleshooting
- **ImagePullBackOff**: verify the image URI and that the node role has `AmazonEC2ContainerRegistryReadOnly`.
- **CrashLoopBackOff / probe failures**: `kubectl logs -l app=modresorts -n modresorts`; check memory limits (JVM uses 75% of container memory) and startup time (startupProbe allows ~3 min).
- **Service unreachable**: `kubectl get endpoints modresorts-service -n modresorts`; confirm selector `app=modresorts`.
- **Ingress has no address**: confirm the AWS Load Balancer Controller is running (`kubectl get pods -n kube-system | grep load-balancer`) and subnets are tagged for ELB; `kubectl describe ingress modresorts-ingress -n modresorts`.

## 9. Configuration
| Variable | Purpose | Default |
|---|---|---|
| `SERVER_PORT` | HTTP port | 8080 |
| `SPRING_PROFILES_ACTIVE` | Spring profile | docker |
| `JAVA_OPTS` | JVM flags | container-aware, 75% RAM |
| `WEATHER_API_KEY` | Weather service key | empty |
| `SERVER_NAME` | Server name displayed | empty (falls back to HOSTNAME) |
| `TZ` | Timezone | UTC |

## 10. Security
- Container runs as non-root; no package managers or tools added.
- For sensitive values such as `WEATHER_API_KEY`, prefer a Kubernetes Secret (`secretKeyRef`) over a plain env value.
- Add HTTPS to the ALB via an ACM certificate annotation (`alb.ingress.kubernetes.io/certificate-arn`) and `listen-ports` for 443.
- Note: the codebase contains `FakeX509TrustManager`/`SSLUtils` and log4j-core 2.14.1 (vulnerable to Log4Shell); upgrade before production.
- Wrapper files (`mvnw`, `gradlew`) are not used; builds use system `mvn`.

## 11. Java notes
Java 8u191+ supports `-XX:+UseContainerSupport` and `MaxRAMPercentage`. The Dockerfile also uses a PurgeCSS stage to trim CSS before the Maven build.
