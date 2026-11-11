# ModResorts – Deployment Guide (Docker & AWS EKS)

## Application overview
- Java 8, Maven, Spring Boot 2.7.18 (embedded Tomcat), packaged as executable WAR (`target/modresorts-2.0.0.war`)
- Port: 8080 (Spring Boot default; no custom port configured)
- Health endpoint: `GET /health` (HealthServlet, returns `{"status":"UP"}`); no Actuator dependency
- Environment variables: `WEATHER_API_KEY`, `ENABLE_JMX_MBEAN`, `SERVER_NAME`/`HOSTNAME`
- Runtime base image: `eclipse-temurin:8-jdk` (explicit); builder `maven:3.9.4-eclipse-temurin-8`

## Prerequisites
Docker 20+, AWS CLI v2, kubectl, (optional) eksctl, an EKS cluster with AWS Load Balancer Controller installed, IAM permissions for ECR and `eks:DescribeCluster`.

## Local run with Docker Compose
```
export WEATHER_API_KEY=your-key   # optional
docker compose up --build
curl http://localhost:8080/health
```
Only the application service is defined; external services must be provided separately.

## Build and push
Run from the repository root:
```
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
Choose AWS ECR or Docker Hub; the script sanitizes the tag (lowercase, hyphenated, default `latest`), creates the ECR repo if missing, builds and pushes.

## EKS setup
```
aws eks update-kubeconfig --region <region> --name <cluster>
kubectl cluster-info
```

## Deploy to EKS
```
./scripts/deploy-image.sh      # or scripts\deploy-image.bat
```
The script prompts for region, cluster, image URI and optional env vars, substitutes `{{IMAGE_URI}}`, `{{WEATHER_API_KEY}}`, `{{ENABLE_JMX_MBEAN}}` in a temporary copy of the manifests, then applies namespace → deployment → service → ingress and waits for the rollout.

Manifests (`kubernetes/`):
- `namespace.yaml` – namespace `modresorts`
- `deployment.yaml` – 2 replicas, requests 250m/512Mi, limits 500m/1Gi, HTTP probes on `/health:8080`
- `service.yaml` – ClusterIP, port 80 → 8080
- `ingress.yaml` – ALB ingress (internet-facing, target-type ip); change host `modresorts.example.com`

## Scaling and management
```
kubectl scale deployment/modresorts -n modresorts --replicas=3
kubectl autoscale deployment modresorts -n modresorts --cpu-percent=70 --min=2 --max=6
kubectl set image deployment/modresorts modresorts=<new-image> -n modresorts
kubectl rollout undo deployment/modresorts -n modresorts
```

## Troubleshooting
- Pods not Ready: `kubectl describe pod -n modresorts`, `kubectl logs deploy/modresorts -n modresorts`. JVM startup may need longer probe delays.
- ImagePullBackOff: verify image URI and that node role has ECR read access.
- OOMKilled: raise memory limits and adjust `JAVA_OPTS`.
- Ingress has no address: verify AWS Load Balancer Controller is running (`kubectl get pods -n kube-system`) and subnets are tagged.
- 503 from ALB: check service endpoints `kubectl get endpoints -n modresorts`.

## Configuration
Set env vars in `kubernetes/deployment.yaml`; use Kubernetes Secrets for `WEATHER_API_KEY` in production. `JAVA_OPTS` controls heap (`-Xms256m -Xmx512m`, MaxRAMPercentage 75).

## Security
Container runs as non-root user (uid 1001). No package managers or extra tools in runtime image. Use private ECR, scan images, add TLS (ACM certificate annotation) on the ingress.
Note: the project's pom.xml uses dated dependencies (log4j-core 2.14.1, jackson-databind 2.9.10, commons-collections 3.2.1) with known vulnerabilities; upgrade them. The explicit base image is a JDK image, which is larger than a JRE image.
