# ModResorts - Containerization & AWS EKS Deployment Guide

## Application summary
- Java 8 Maven project, **WAR** packaging (`modresorts-2.0.0.war`), Java EE 7 servlets/filters (no Spring Boot).
- Originally targeted Open Liberty; the container runs the WAR as `ROOT.war` on **Apache Tomcat 9** (Servlet 3.1) copied into the runtime base image `eclipse-temurin:8-jre`.
- HTTP port: **8080**. Health endpoint: **`/health`** (`HealthServlet`, returns `{"status":"UP"}`).
- Environment variables: `WEATHER_API_KEY`, `JNDI_INITIAL_CONTEXT_FACTORY`, `JNDI_PROVIDER_URL`, `SERVER_NAME`, `JAVA_OPTS`.
- `server.xml` (Liberty config) is no longer used by the container image.

## Prerequisites
Docker 20+, AWS CLI v2, kubectl, eksctl (optional), an EKS cluster with the **AWS Load Balancer Controller** installed, and IAM permissions for ECR (`ecr:*` push actions) and `eks:DescribeCluster`.

## Local development (Docker Compose)
```bash
export WEATHER_API_KEY=your-key   # optional
docker compose up --build
# http://localhost:8080/  and  http://localhost:8080/health
```

## Build and push
Run from the repository root:
```bash
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```
Choose AWS ECR or Docker Hub. The script sanitises the tag (lowercase, hyphenated, default `latest`), creates the ECR repository if missing, builds with `docker build -f Dockerfile -t <image> .` and pushes.

## Deploy to EKS
```bash
./scripts/deploy-image.sh      # Linux/macOS
scripts\deploy-image.bat       # Windows
```
The script prompts for region, cluster, image URI and optional env values, substitutes `{{PLACEHOLDERS}}` in a temporary copy of `kubernetes/*.yaml`, runs `aws eks update-kubeconfig`, applies namespace -> deployment -> service -> ingress, waits for the rollout and prints resources.

Manifests:
- `namespace.yaml` - namespace `modresorts`.
- `deployment.yaml` - 2 replicas, requests 250m/512Mi, limits 500m/1Gi, HTTP probes on `/health`.
- `service.yaml` - ClusterIP, port 80 -> 8080.
- `ingress.yaml` - ALB (internet-facing, target-type ip, health check `/health`), host `modresorts.example.com`. Edit the host (or remove the `host` line) for your DNS.

## Troubleshooting
- `kubectl get pods -n modresorts`, `kubectl describe pod <pod> -n modresorts`, `kubectl logs <pod> -n modresorts`.
- **ImagePullBackOff**: node role needs ECR read access; verify image URI/tag.
- **CrashLoopBackOff / probe failures**: Tomcat start takes 20-40s; check logs; adjust `initialDelaySeconds`; check memory limit vs `JAVA_OPTS`.
- **Ingress has no address**: confirm AWS Load Balancer Controller is running (`kubectl get pods -n kube-system`) and subnets are tagged for ELB.
- **503 from ALB**: check target group health; path `/health` must return 200.

## Scaling and management
```bash
kubectl scale deployment/modresorts -n modresorts --replicas=4
kubectl autoscale deployment modresorts -n modresorts --cpu-percent=70 --min=2 --max=6
kubectl set image deployment/modresorts modresorts=<new-image> -n modresorts
kubectl rollout undo deployment/modresorts -n modresorts
```

## Configuration and security
- The image runs as non-root UID 1001; no packages are installed in the runtime stage; no HEALTHCHECK (Kubernetes probes are used).
- Store `WEATHER_API_KEY` in a Kubernetes Secret / AWS Secrets Manager for production rather than a plain env value.
- `FakeX509TrustManager` and `log4j-core 2.14.1` (vulnerable to Log4Shell), `jackson-databind 2.9.10` and `commons-collections 3.2.1` are outdated; upgrade before production use.
- Login security constraints in `web.xml` are commented out (demo setup).
- Add TLS on the ALB with an ACM certificate (`alb.ingress.kubernetes.io/certificate-arn`).

## Java notes
JVM flags: `-Xms256m -Xmx512m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0`, `TZ=UTC`, UTF-8. Tune via `JAVA_OPTS`.
