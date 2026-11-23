# TestComp1 (ModResorts) - Deployment Guide for AWS EKS

## 1. Application overview
- Type: Java EE 7 / Servlet 3.1 web application packaged as a WAR (Maven, Java 8)
- Runtime: Apache Tomcat 9 (copied from `tomcat:9.0-jdk8-temurin`) on `eclipse-temurin:8-jdk` (explicit base image)
- Port: 8080 (Tomcat default)
- Health endpoint: `GET /health` (returns `{"status":"UP"}`)
- External configuration (environment variables): `WEATHER_API_KEY`, `SERVER_NAME`, `JNDI_INITIAL_CONTEXT_FACTORY`, `JNDI_PROVIDER_URL`

## 2. Prerequisites
- Docker 20.10+
- AWS CLI v2, configured (`aws configure`) with permissions for ECR and EKS
- kubectl matching your cluster version
- eksctl (optional, for creating clusters)
- An EKS cluster with the AWS Load Balancer Controller installed (needed for the ALB ingress)
- IAM: `ecr:*` (push), `eks:DescribeCluster`, and a cluster access entry / aws-auth mapping for your IAM identity

## 3. Local development with Docker Compose
```bash
export WEATHER_API_KEY=your-key   # optional
docker compose up --build
# http://localhost:8080/  and  http://localhost:8080/health
```
Only the application service is defined; external services must be provided separately.

## 4. Build and push the image
```bash
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
Run from the repository root. Choose 1 (AWS ECR) or 2 (Docker Hub). The tag is sanitized (lowercase, hyphenated, default `latest`). For ECR the repository is created automatically if it does not exist.

## 5. EKS setup
```bash
eksctl create cluster --name my-cluster --region us-east-1 --nodes 2   # optional
aws eks update-kubeconfig --region us-east-1 --name my-cluster
kubectl cluster-info
```

## 6. Deploy to EKS
```bash
./scripts/deploy-image.sh      # Linux/macOS
scripts\deploy-image.bat       # Windows
```
The script prompts for region, cluster, image URI and the environment variables, substitutes the `{{PLACEHOLDER}}` values in a temporary copy of the manifests, then applies them in order: namespace, deployment, service, ingress. It waits for the rollout and prints the resources.

Manifests (`kubernetes/`):
| File | Purpose |
|------|---------|
| namespace.yaml | Namespace `testcomp1` |
| deployment.yaml | 2 replicas, 250m/512Mi requests, 500m/1Gi limits, startup/liveness/readiness probes on `/health:8080` |
| service.yaml | ClusterIP service, port 80 -> 8080 |
| ingress.yaml | ALB ingress (internet-facing); edit the host `testcomp1.example.com` for your domain |

Get the URL: `kubectl get ingress testcomp1-ingress -n testcomp1`

## 7. Configuration
| Variable | Description |
|----------|-------------|
| WEATHER_API_KEY | Enables real-time weather data; mock data is used when empty |
| SERVER_NAME | Server name shown by the app (defaults to the pod hostname) |
| JNDI_INITIAL_CONTEXT_FACTORY | JNDI factory (default `org.apache.naming.java.javaURLContextFactory`) |
| JNDI_PROVIDER_URL | Optional JNDI provider URL (e.g. a Kubernetes service DNS name) |
| JAVA_OPTS | JVM flags; defaults use `-XX:MaxRAMPercentage=75.0` |

For sensitive values such as `WEATHER_API_KEY`, prefer a Kubernetes Secret (`secretKeyRef`) or AWS Secrets Manager over plain env values.

## 8. Scaling and management
```bash
kubectl scale deployment/testcomp1 -n testcomp1 --replicas=4
kubectl autoscale deployment testcomp1 -n testcomp1 --cpu-percent=70 --min=2 --max=6   # needs metrics-server
kubectl set image deployment/testcomp1 testcomp1=<new-image-uri> -n testcomp1          # rolling update
kubectl rollout status deployment/testcomp1 -n testcomp1
kubectl rollout undo deployment/testcomp1 -n testcomp1                                 # rollback
```

## 9. Troubleshooting
- Pods `ImagePullBackOff`: check the image URI and that the node role has `AmazonEC2ContainerRegistryReadOnly`.
- Pods `CrashLoopBackOff`: `kubectl logs deployment/testcomp1 -n testcomp1`; check memory limits (OOMKilled) and JAVA_OPTS.
- Readiness failing: `kubectl port-forward deploy/testcomp1 8080:8080 -n testcomp1` then `curl localhost:8080/health`.
- Service has no endpoints: `kubectl get endpoints -n testcomp1`; verify selector `app: testcomp1`.
- Ingress has no address: confirm the AWS Load Balancer Controller is running (`kubectl get pods -n kube-system | grep load-balancer`), check `kubectl describe ingress -n testcomp1`, and that subnets are tagged for ELB.
- `kubectl` unauthorized: re-run `aws eks update-kubeconfig` and verify your IAM identity has cluster access.

## 10. Security notes
- The container runs as a non-root user (`appuser`).
- No package managers or extra tools are installed in the runtime image.
- Dependencies in `pom.xml` include old versions (e.g. log4j-core 2.14.1, jackson-databind 2.9.10, commons-collections 3.2.1) with known vulnerabilities; upgrade them before production use.
- Add TLS to the ingress (ACM certificate annotation `alb.ingress.kubernetes.io/certificate-arn`) and restrict access as needed.
- Application security (form login) is disabled in `web.xml` for demo purposes.

## 11. Java notes
- WAR is built with `mvn clean package -DskipTests`; the exploded webapp `target/modresorts-2.0.0` is deployed as Tomcat `ROOT`.
- Tomcat 9 is required because the application uses the `javax.*` namespace (Tomcat 10+ uses `jakarta.*`).
- JVM is container-aware (`-XX:+UseContainerSupport`, `MaxRAMPercentage=75.0`); timezone is UTC.
- Maven/Gradle wrapper files are intentionally excluded from the image build via `.dockerignore`.
