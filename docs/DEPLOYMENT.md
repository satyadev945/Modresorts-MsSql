# ModResorts – Deployment Guide (Docker & AWS EKS)

ModResorts is a Java EE 7 / Servlet 3.1 web application (Maven, WAR packaging, Java 8). The container runs the WAR as the ROOT context on Apache Tomcat 9 (javax.* namespace) on top of `eclipse-temurin:8-jdk-alpine`.

* Port: **8080** (Tomcat default; no override in application config)
* Health endpoint: **`/health`** (`HealthServlet`, returns `{"status":"UP"}`)
* Image build: multi-stage (Maven builder -> Tomcat distribution -> runtime), non-root user `app`

## 1. Prerequisites
- Docker 20.10+
- AWS CLI v2 (configured: `aws configure`), kubectl, optionally eksctl
- IAM permissions: ECR (create/push), `eks:DescribeCluster`, and cluster access mapped in `aws-auth`/access entries
- EKS cluster with the AWS Load Balancer Controller installed (for the ALB Ingress)

## 2. Local development (Docker Compose)
```bash
docker compose up --build
# open http://localhost:8080 ; health: http://localhost:8080/health
```
Optional environment variables (export before running): `WEATHER_API_KEY`, `WEATHER_SERVICE_URL`, `SERVER_DISPLAY_NAME`, `SERVER_FULL_NAME`, `JNDI_INITIAL_CONTEXT_FACTORY`, `JNDI_PROVIDER_URL`.
The compose file defines only the application; external services are supplied via environment variables.

## 3. Build and push the image
Run from the repository root:
```bash
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
Choose AWS ECR (repository auto-created if missing) or Docker Hub. Tags are lower-cased and sanitised; empty -> `latest`.

## 4. Deploy to AWS EKS
```bash
./scripts/deploy-image.sh      # Linux/macOS
scripts\deploy-image.bat       # Windows
```
The script prompts for region, cluster name, image URI, ingress host and optional env vars, substitutes `{{PLACEHOLDER}}` values in a temporary copy of `kubernetes/*.yaml`, runs `aws eks update-kubeconfig`, applies manifests in order (namespace -> deployment -> service -> ingress), waits for the rollout and prints resources and the ALB address.

### Manifests
| File | Purpose |
|------|---------|
| `kubernetes/namespace.yaml` | Namespace `modresorts` |
| `kubernetes/deployment.yaml` | 2 replicas, requests 250m/512Mi, limits 500m/1Gi, HTTP probes on `/health:8080` |
| `kubernetes/service.yaml` | ClusterIP, port 80 -> 8080 |
| `kubernetes/ingress.yaml` | ALB (internet-facing, target-type ip, health check `/health`) |

## 5. Configuration
| Variable | Purpose |
|----------|---------|
| `WEATHER_API_KEY` | Enables real-time weather lookup; otherwise bundled sample data is used |
| `WEATHER_SERVICE_URL` | Delegates weather requests to an external service |
| `SERVER_DISPLAY_NAME`, `SERVER_FULL_NAME` | Display name shown by the app (defaults to `HOSTNAME`) |
| `JNDI_INITIAL_CONTEXT_FACTORY`, `JNDI_PROVIDER_URL` | Optional JNDI configuration |
| `JAVA_OPTS` | JVM flags (container-aware, `MaxRAMPercentage=75`) |

Use Kubernetes Secrets (or AWS Secrets Manager / External Secrets) for `WEATHER_API_KEY` in production instead of plain env values.

## 6. Operations
```bash
kubectl get pods,svc,ingress -n modresorts
kubectl logs deploy/modresorts -n modresorts
kubectl rollout undo deployment/modresorts -n modresorts       # rollback
kubectl set image deployment/modresorts modresorts=<new-image> -n modresorts   # rolling update
kubectl scale deployment/modresorts --replicas=4 -n modresorts
kubectl autoscale deployment modresorts --cpu-percent=70 --min=2 --max=6 -n modresorts   # HPA (needs metrics-server)
```

## 7. Troubleshooting
- **Pods CrashLoopBackOff / not Ready**: `kubectl describe pod`, `kubectl logs`; Tomcat start takes ~20-40 s – adjust probe delays if the node is slow.
- **ImagePullBackOff**: verify the image URI and that node IAM role has `AmazonEC2ContainerRegistryReadOnly`.
- **Ingress has no address**: confirm the AWS Load Balancer Controller is running (`kubectl get pods -n kube-system`), subnets are tagged for ELB.
- **ALB targets unhealthy**: the health path is `/health` on port 8080; check security groups allow ALB -> pod traffic.
- **OOMKilled**: raise memory limit; heap is capped at 75% of the container limit.

## 8. Security notes
- Container runs as non-root user `app`; no extra packages installed in the runtime image.
- Pin image tags (avoid `latest`) in production; scan images in ECR.
- Terminate TLS at the ALB (add ACM certificate annotation and 443 listener).
- The app writes `reservations.zip` to the user's home (`/home/app`, ephemeral); mount a volume if persistence is required.
- Known vulnerable dependencies in `pom.xml` (e.g. log4j-core 2.14.1, jackson-databind 2.9.10, commons-collections 3.2.1) should be upgraded.
- Note: `javaee-api` is `provided`; Tomcat supplies the Servlet API. Liberty-specific descriptors (`ibm-web-*.xml`) are ignored by Tomcat; JNDI data sources (`ModResortsCustomerInformation`) require configuration if used.
