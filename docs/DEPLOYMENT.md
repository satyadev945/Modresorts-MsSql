# TestComp1 (ModResorts) – Deployment Guide for AWS EKS

## 1. Application overview
- Type: Java 8 servlet/JSP web application packaged as a **WAR** (`modresorts-2.0.0`), built with **Maven**
- Runtime: Apache Tomcat 9 on `eclipse-temurin:8-jre` (explicit base image)
- Port: **8080** (Tomcat default); health endpoint: **`/health`** (`HealthServlet`, returns `{"status":"UP"}`)
- Optional environment variables: `WEATHER_API_KEY`, `WEATHER_SERVICE_URL`, `SERVER_NAME`, `SERVER_FULL_NAME`, `JNDI_INITIAL_CONTEXT_FACTORY`, `JNDI_PROVIDER_URL`
- The Dockerfile has four stages: PurgeCSS → Maven build → Tomcat binaries source → runtime.

## 2. Prerequisites
- Docker 20.10+, Maven not required locally (build occurs in Docker)
- AWS CLI v2 configured (`aws configure`), kubectl, optionally eksctl
- IAM permissions: `ecr:*` (push), `eks:DescribeCluster`, and access to the cluster (aws-auth / access entries)
- An EKS cluster with the **AWS Load Balancer Controller** installed (required for the ALB Ingress)

## 3. Local development with Docker Compose
```bash
export WEATHER_API_KEY=""          # optional
docker compose up --build
curl http://localhost:8080/health
```
Open http://localhost:8080 . Stop with `docker compose down`.

## 4. Build and push the image
From the repository root:
```bash
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
The script asks for the registry (1 = AWS ECR, 2 = Docker Hub), an image tag (default `latest`, sanitized to lowercase), and registry details. For ECR the repository is created if missing. The final image URI is printed.

## 5. EKS cluster setup
```bash
eksctl create cluster --name my-cluster --region us-east-1 --nodes 2
aws eks update-kubeconfig --region us-east-1 --name my-cluster
kubectl cluster-info
```
Install the AWS Load Balancer Controller following the AWS documentation (IAM policy, service account, Helm chart).

## 6. Deploy to EKS
```bash
./scripts/deploy-image.sh      # Linux/macOS
scripts\deploy-image.bat       # Windows
```
The script prompts for region, cluster name, image URI and optional env values (`WEATHER_API_KEY`, `WEATHER_SERVICE_URL`), renders the manifests in a temporary directory (placeholders `{{IMAGE_URI}}`, `{{WEATHER_API_KEY}}`, `{{WEATHER_SERVICE_URL}}`), configures kubectl, applies manifests in order and waits for the rollout.

| Manifest | Purpose |
|---|---|
| `kubernetes/namespace.yaml` | Namespace `testcomp1` |
| `kubernetes/deployment.yaml` | 2 replicas, requests 250m/512Mi, limits 500m/1Gi, startup/liveness/readiness probes on `/health:8080` |
| `kubernetes/service.yaml` | ClusterIP service port 80 → 8080 |
| `kubernetes/ingress.yaml` | ALB internet-facing ingress, health check path `/health`, host `testcomp1.example.com` |

Edit the host in `ingress.yaml` (or remove the `host` rule) to match your DNS. Get the ALB address with `kubectl get ingress -n testcomp1`.

## 7. Operations
```bash
kubectl get pods,svc,ingress -n testcomp1
kubectl logs -f deployment/testcomp1 -n testcomp1
kubectl scale deployment/testcomp1 --replicas=4 -n testcomp1
kubectl autoscale deployment testcomp1 --cpu-percent=70 --min=2 --max=6 -n testcomp1   # HPA (needs metrics-server)
kubectl set image deployment/testcomp1 testcomp1=<new-image-uri> -n testcomp1          # rolling update
kubectl rollout undo deployment/testcomp1 -n testcomp1                                 # rollback
```

## 8. Troubleshooting
- **Pods `ImagePullBackOff`**: check the image URI/tag; ensure node IAM role has `AmazonEC2ContainerRegistryReadOnly`; for Docker Hub private repos create an imagePullSecret.
- **Pods `CrashLoopBackOff` / not ready**: `kubectl describe pod` and `kubectl logs`; Tomcat startup typically needs 20-40s; probes allow up to ~150s via the startupProbe.
- **`OOMKilled`**: raise the memory limit; JVM uses `MaxRAMPercentage=75`.
- **Service has no endpoints**: verify the selector `app: testcomp1` matches pod labels (`kubectl get endpoints -n testcomp1`).
- **Ingress has no address**: confirm the AWS Load Balancer Controller is running (`kubectl get pods -n kube-system`), and subnets are tagged for ELB discovery.
- **ALB targets unhealthy**: check `/health` returns 200 and security groups allow ALB → pod port 8080.

## 9. Configuration management
Values are passed as environment variables. For sensitive values (e.g. `WEATHER_API_KEY`) prefer a Kubernetes Secret (`kubectl create secret generic ...` and `valueFrom.secretKeyRef`) or AWS Secrets Manager with the Secrets Store CSI driver instead of plain env values.

## 10. Security considerations
- The container runs as non-root user `appuser` (UID 1001).
- The runtime has no package manager changes and no health-check tooling; probes are handled by Kubernetes.
- Dependencies in `pom.xml` include old versions (e.g. log4j-core 2.14.1, jackson-databind 2.9.10, commons-collections 3.2.1, spring 5.3.x) with known CVEs – upgrade them before production.
- Add TLS by adding an ACM certificate annotation (`alb.ingress.kubernetes.io/certificate-arn`) and HTTPS listen port.
- Do not commit credentials; scripts read secrets interactively.

## 11. Java-specific notes
- JVM flags are set via `JAVA_OPTS` (`-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Xms256m -Duser.timezone=UTC`).
- `catalina.sh run` runs Tomcat in the foreground and handles SIGTERM for graceful shutdown (terminationGracePeriodSeconds 30).
- The app is deployed as `ROOT.war`, so it is served at `/`.
- Several classes reference EJB/JNDI/JMX APIs; JNDI datasources (e.g. `jdbc/ModResortsJndi`) are not configured in Tomcat by default.
