# ModResorts (modresorts) – Container & AWS EKS Deployment Guide

## 1. Application Overview
- Java 8 servlet application packaged as a **WAR** (`modresorts-2.0.0.war`), built with **Maven**.
- Runs on **Apache Tomcat 9** (javax.servlet) inside an `eclipse-temurin:8-jdk` runtime image (explicit base image).
- Port **8080**; health endpoint **`/health`** (returns `{"status":"UP"}`), served by `HealthServlet`.
- Environment variables read by the app: `WEATHER_API_KEY`, `SERVER_NAME` (and `HOSTNAME`, set by Kubernetes).
- SQL Server driver (`mssql-jdbc`) is bundled; the DB itself is external and not part of these artifacts.

## 2. Prerequisites
Docker 20+, AWS CLI v2, kubectl, (optional) eksctl, an AWS account with permissions for ECR, EKS (`eks:DescribeCluster`) and an EKS cluster with the **AWS Load Balancer Controller** installed.

## 3. Local Development (Docker Compose)
```
export WEATHER_API_KEY=<key>   # optional
docker compose up --build
curl http://localhost:8080/health
```
Only the application service is defined; external services must be supplied through environment variables.

## 4. Build and Push
Run from the repository root:
```
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
You are prompted for the tag (sanitized, default `latest`), registry (1. AWS ECR / 2. Docker Hub) and credentials. For ECR the repository is created automatically if missing.

## 5. EKS Setup
```
aws eks update-kubeconfig --region <region> --name <cluster>
kubectl cluster-info
```
Example cluster creation: `eksctl create cluster --name modresorts --region us-east-1 --nodes 2`.
Install the AWS Load Balancer Controller so the `alb` ingress class works.

## 6. Deploy
```
./scripts/deploy-image.sh      # or scripts\deploy-image.bat
```
The script prompts for region, cluster, image URI and optional env vars, renders the `{{PLACEHOLDER}}` values into a temporary copy of the manifests, applies them in order (namespace → deployment → service → ingress), waits for the rollout and prints the ALB hostname.

Manifests (`kubernetes/`):
| File | Purpose |
|------|---------|
| namespace.yaml | `modresorts` namespace |
| deployment.yaml | 2 replicas, requests 250m/512Mi, limits 500m/1Gi, startup/liveness/readiness probes on `/health:8080` |
| service.yaml | ClusterIP, port 80 → 8080 |
| ingress.yaml | ALB internet-facing ingress, health check `/health` |

## 7. Operations
- Scale: `kubectl scale deployment/modresorts -n modresorts --replicas=4`
- HPA: `kubectl autoscale deployment modresorts -n modresorts --cpu-percent=70 --min=2 --max=6` (requires metrics-server)
- Rolling update: re-run deploy with a new image tag.
- Rollback: `kubectl rollout undo deployment/modresorts -n modresorts`

## 8. Troubleshooting
- **Pods Pending**: `kubectl describe pod -n modresorts <pod>`; check node capacity.
- **ImagePullBackOff**: verify image URI and that node IAM role has `AmazonEC2ContainerRegistryReadOnly`.
- **CrashLoop / probe failures**: `kubectl logs -n modresorts <pod>`; Tomcat startup may take 20–40s (startupProbe allows 150s).
- **Ingress has no address**: confirm AWS Load Balancer Controller is running (`kubectl get pods -n kube-system`) and subnets are tagged for ELB.
- **502/504 from ALB**: confirm target-type `ip` targets are healthy on `/health`.

## 9. Configuration
Set `WEATHER_API_KEY` and `SERVER_NAME` via deploy prompts. For secrets prefer a Kubernetes Secret / AWS Secrets Manager rather than plain env values. JVM tuning via `JAVA_OPTS` (default `-Xms256m -Xmx512m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0`). Timezone `TZ=UTC`.

## 10. Security
Container runs as non-root user `modres`; no wrapper scripts or package tools are used; use private ECR repos, restrict ingress with security groups/WAF, enable TLS via ACM (`alb.ingress.kubernetes.io/certificate-arn`, listen on 443). Note: the pom pins some outdated libraries (e.g. log4j-core 2.14.1, jackson-databind 2.9.10) with known CVEs – upgrade before production use.

## 11. Java-specific notes
- WAR deployed as `ROOT.war` so the app is served at `/`.
- The Dockerfile pulls Tomcat from `tomcat:9.0-jdk8-temurin` because the explicit base image has no servlet container.
- `WebContent/` is the WAR source directory; `WEB-INF/ibm-*.xml` descriptors are ignored by Tomcat.
- `AvailabilityCheckerServlet` uses `user.home` (`/home/modres`), which is ephemeral in containers.
