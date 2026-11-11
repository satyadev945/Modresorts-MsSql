# ModResorts – Deployment Guide (AWS EKS)

## Application overview
- Java 8 WAR (`modresorts-2.0.0.war`, Maven, Servlet 3.1 / Java EE 7 APIs, JSP).
- Packaged in a multi-stage image: PurgeCSS stage -> Maven build stage -> `eclipse-temurin:8-jre` runtime running the WAR with an embedded Tomcat 9 (`webapp-runner`) as non-root user (UID 1001).
- Listens on port **9080**, context root `/`. Health endpoint: `GET /health` (returns `{"status":"UP"}`).
- Configuration through environment variables: `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` (optional cache), `WEATHER_API_KEY` (optional; falls back to bundled data), `SERVER_NAME`, `JAVA_OPTS`, `APP_PORT`.

## Prerequisites
- Docker 20.10+, AWS CLI v2, kubectl, eksctl (optional)
- IAM permissions: ECR (push/create repository), `eks:DescribeCluster`, and cluster RBAC access
- An EKS cluster with the AWS Load Balancer Controller installed (for the ALB Ingress)

## Local run (Docker Compose)
```
docker compose up --build
```
Open http://localhost:9080/ and http://localhost:9080/health. Set Redis/weather variables in your shell or an `.env` file. Only the application service is defined; external services are provided separately.

## Build and push
Run from the repository root:
```
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
Choose AWS ECR or Docker Hub; tags are sanitized (lowercase, default `latest`). The ECR repository is created automatically if missing.

## Deploy to EKS
```
./scripts/deploy-image.sh      # Linux/macOS
scripts\deploy-image.bat       # Windows
```
The script prompts for region, cluster, image URI and optional environment values, substitutes the `{{IMAGE_URI}}`, `{{REDIS_*}}`, `{{WEATHER_API_KEY}}` placeholders in a temporary copy of the manifests, configures kubectl (`aws eks update-kubeconfig`), and applies namespace -> deployment -> service -> ingress, then waits for rollout.

Manifests (`kubernetes/`): namespace `modresorts`; Deployment (2 replicas, 250m/512Mi requests, 500m/1Gi limits, HTTP probes on `/health`:9080); ClusterIP Service 80 -> 9080; ALB Ingress (host `modresorts.example.com` – change it to your domain, or remove the host rule to use the ALB DNS name).

## Operations
- Scale: `kubectl scale deployment/modresorts -n modresorts --replicas=4` or create an HPA (`kubectl autoscale deployment modresorts -n modresorts --cpu-percent=70 --min=2 --max=6`).
- Update: push a new tag and re-run deploy script (rolling update).
- Roll back: `kubectl rollout undo deployment/modresorts -n modresorts`.

## Troubleshooting
- Pods `ImagePullBackOff`: verify the image URI and that node role has `AmazonEC2ContainerRegistryReadOnly`.
- Pods `CrashLoopBackOff` / probe failures: `kubectl logs -n modresorts deploy/modresorts`, `kubectl describe pod`. Increase probe `initialDelaySeconds` if the JVM is slow to start.
- `OOMKilled`: raise memory limit; heap is 75% of container memory (`MaxRAMPercentage`).
- Ingress has no address: check AWS Load Balancer Controller logs (`kubectl logs -n kube-system deploy/aws-load-balancer-controller`) and subnet tags.
- Service check: `kubectl port-forward -n modresorts svc/modresorts-service 8080:80`.

## Security notes
- Container runs as non-root; no extra packages are installed in the runtime image.
- Redis password and weather API key are passed as env values by the deploy script; for production, move them into a Kubernetes Secret / AWS Secrets Manager and reference with `secretKeyRef`.
- Terminate TLS at the ALB with an ACM certificate (`alb.ingress.kubernetes.io/certificate-arn`).
- The codebase includes outdated dependencies (e.g. log4j-core 2.14.1, jackson-databind 2.9.10, commons-collections 3.2.1) with known CVEs; upgrade them before production use.

## Java notes
- Tune with `JAVA_OPTS` (default `-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0`). Timezone `TZ=UTC`.
- The WAR was originally built for WebSphere/Liberty; the image uses embedded Tomcat, so WebSphere-/Liberty-specific descriptors (`ibm-web-*.xml`) are ignored.
