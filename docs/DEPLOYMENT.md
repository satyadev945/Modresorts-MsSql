# ModResorts – Container & AWS EKS Deployment Guide

## Application summary
- Java 8 Maven project, packaged as a **WAR** (`modresorts-2.0.0.war`), Java EE 7 servlets (javax.servlet 3.1)
- Runs in the container on an embedded Tomcat 9 launcher (`webapp-runner`) on the base image `eclipse-temurin:8-jdk-alpine`
- Port **9080**, served at the root context (`/`); health endpoint **`/health`** (`HealthServlet`, returns `{"status":"UP"}`)
- External services via env vars: `REDIS_HOST`, `REDIS_PORT`, `REDIS_CACHE_TTL`, `WEATHER_API_KEY` (and optional `JNDI_INITIAL_CONTEXT_FACTORY`, `JNDI_PROVIDER_URL`, `SERVER_NAME`)

## Prerequisites
Docker, AWS CLI v2 (configured), kubectl, optionally eksctl; IAM permissions for ECR (push) and EKS (`eks:DescribeCluster`) and a cluster with the **AWS Load Balancer Controller** installed.

## Local development
```
docker compose up --build
# http://localhost:9080/   health: http://localhost:9080/health
```
Set `REDIS_HOST`, `WEATHER_API_KEY` etc. in your shell or a `.env` file. Only the application is defined; Redis must be provided separately.

## Build and push
Run from the repository root:
```
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
Choose ECR or Docker Hub, supply a tag (default `latest`). The ECR repository is created automatically if missing. The script prints the full image URI.

## Deploy to EKS
```
./scripts/deploy-image.sh      # or scripts\deploy-image.bat
```
The script prompts for region, cluster name, image URI, app environment variables and ingress host, substitutes placeholders (`{{IMAGE_URI}}`, `{{REDIS_HOST}}`, ...) in a temporary copy of `kubernetes/`, runs `aws eks update-kubeconfig`, applies namespace → deployment → service → ingress, waits for rollout and prints resources.

Manifests (`kubernetes/`):
- `namespace.yaml` – namespace `modresorts`
- `deployment.yaml` – 2 replicas, requests 250m/512Mi, limits 500m/1Gi, HTTP liveness/readiness on `/health:9080`
- `service.yaml` – ClusterIP, 80 → 9080
- `ingress.yaml` – ALB (internet-facing, ip target type), health check `/health`

## Troubleshooting
- Pods `ImagePullBackOff`: check node role has `AmazonEC2ContainerRegistryReadOnly` and the image URI/tag.
- `CrashLoopBackOff`: `kubectl logs -l app=modresorts -n modresorts`; check heap vs. memory limit (`MaxRAMPercentage=75`).
- Probes failing: JVM startup is slow, raise `initialDelaySeconds`.
- No ingress address: verify the AWS Load Balancer Controller is running (`kubectl get pods -n kube-system`) and subnets are tagged.
- Redis errors: verify `REDIS_HOST`/`REDIS_PORT` reachable from the pods' VPC/security groups.

## Scaling and management
```
kubectl scale deployment/modresorts -n modresorts --replicas=4
kubectl autoscale deployment modresorts -n modresorts --cpu-percent=70 --min=2 --max=6
kubectl rollout status deployment/modresorts -n modresorts
kubectl rollout undo deployment/modresorts -n modresorts
```

## Configuration and security
- The container runs as non-root user `appuser`; no HEALTHCHECK or extra packages in the image.
- `WEATHER_API_KEY` is currently injected as a plain env value; for production move it to a Kubernetes Secret (`secretKeyRef`) or AWS Secrets Manager.
- Use TLS on the ALB (`alb.ingress.kubernetes.io/certificate-arn`, listen-ports 443).
- Note: `pom.xml` pins dependencies with known vulnerabilities (e.g. log4j-core 2.14.1, jackson-databind 2.9.10, spring-webmvc 5.3.17); upgrade them before production.
- The Liberty-specific descriptors in `WebContent/WEB-INF/ibm-*` are ignored by Tomcat. JNDI datasources defined by Liberty are not available; use env vars.
