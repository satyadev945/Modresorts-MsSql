# TestComp1 (ModResorts) - Deployment Guide for AWS EKS

## 1. Application overview

| Item | Value |
|------|-------|
| Type | Java EE 7 style servlet web application (WAR, `modresorts-2.0.0.war`) |
| Build tool | Maven (system `mvn`, no wrapper) |
| Java | 8 |
| Runtime | Apache Tomcat 9 (javax.servlet) on `eclipse-temurin:8-jre` |
| Port | 8080 (context root `/`) |
| Health endpoint | `GET /health` -> `{"status":"UP"}` (`HealthServlet`) |
| External services | Redis / ElastiCache (`REDIS_HOST`, `REDIS_PORT`), Weather API (`WEATHER_API_KEY`) |

## 2. Prerequisites

- Docker 20.10+
- AWS CLI v2 configured (`aws configure`) with permissions for ECR and EKS
- kubectl matching your cluster version
- eksctl (optional, for cluster creation)
- An EKS cluster with the **AWS Load Balancer Controller** installed (required by `ingress.yaml`)

## 3. Repository layout

```
Dockerfile                  Multi-stage build (Maven -> PurgeCSS -> Tomcat -> eclipse-temurin:8-jre)
docker-compose.yml          Local run, application only
.dockerignore
kubernetes/                 namespace, deployment, service, ingress
scripts/                    build-push and deploy-image (.sh / .bat)
docs/DEPLOYMENT.md          this guide
```

## 4. Local run with Docker Compose

```bash
export REDIS_HOST=<redis-host>        # optional
export WEATHER_API_KEY=<key>          # optional
docker compose up --build
```

Open http://localhost:8080/ and http://localhost:8080/health. Redis and any other
infrastructure are NOT part of the compose file; provide them separately.

## 5. Build and push the image

Run from the repository root.

```bash
chmod +x scripts/*.sh
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```

The script asks for the tag (default `latest`, sanitized to lowercase/hyphens), then the
registry (1. AWS ECR, 2. Docker Hub). For ECR it logs in and creates the repository if it
does not exist. At the end it prints the full image URI.

## 6. Deploy to EKS

```bash
./scripts/deploy-image.sh      # Linux/macOS
scripts\deploy-image.bat       # Windows
```

The script prompts for AWS region, cluster name, image URI and optional settings
(`REDIS_HOST`, `REDIS_PORT`, `SERVER_DISPLAY_NAME`, `WEATHER_API_KEY`, ingress host). It:

1. Copies `kubernetes/` to a temp directory and replaces `{{IMAGE_URI}}`, `{{REDIS_HOST}}`, `{{REDIS_PORT}}`, `{{SERVER_DISPLAY_NAME}}`, `{{INGRESS_HOST}}`.
2. Runs `aws eks update-kubeconfig` and `kubectl cluster-info`.
3. Applies namespace -> (weather secret) -> deployment -> service -> ingress.
4. Waits for `kubectl rollout status deployment/testcomp1 -n testcomp1`.
5. Prints pods/services/ingress and the ALB hostname.

### Manifests

| File | Purpose |
|------|---------|
| `namespace.yaml` | Namespace `testcomp1` |
| `deployment.yaml` | 2 replicas, requests 250m/512Mi, limits 500m/1Gi, HTTP probes on `/health:8080` |
| `service.yaml` | ClusterIP, port 80 -> 8080 |
| `ingress.yaml` | ALB (internet-facing, target-type ip, health check `/health`) |

## 7. Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `REDIS_HOST` | Redis/ElastiCache host used by `ModResortsCustomerInformation` | empty |
| `REDIS_PORT` | Redis port (must be numeric) | 6379 |
| `WEATHER_API_KEY_NAME` | Name of the env var holding the weather API key | `WEATHER_API_KEY` |
| `WEATHER_API_KEY` | Weather API key (stored in Kubernetes Secret `testcomp1-weather-secret`) | none |
| `SERVER_DISPLAY_NAME` / `SERVER_FULL_NAME` | Display names in the weather response | pod hostname |
| `JNDI_INITIAL_CONTEXT_FACTORY` / `JNDI_PROVIDER_URL` | Optional JNDI settings | none |
| `JAVA_OPTS` | JVM flags (`-XX:MaxRAMPercentage=75.0` etc.) | see Dockerfile |

## 8. Scaling and management

```bash
kubectl scale deployment/testcomp1 -n testcomp1 --replicas=4
kubectl autoscale deployment testcomp1 -n testcomp1 --cpu-percent=70 --min=2 --max=6   # needs metrics-server
kubectl set image deployment/testcomp1 testcomp1=<new-image> -n testcomp1
kubectl rollout status deployment/testcomp1 -n testcomp1
kubectl rollout undo deployment/testcomp1 -n testcomp1
```

## 9. Troubleshooting

| Symptom | Checks |
|---------|--------|
| `ImagePullBackOff` | Image URI correct? Node role has `AmazonEC2ContainerRegistryReadOnly`? Same region/account? |
| `CrashLoopBackOff` | `kubectl logs deploy/testcomp1 -n testcomp1`; check memory limit vs JVM; `REDIS_PORT` must be numeric |
| Pods not Ready | Probes hit `/health` on 8080; increase `initialDelaySeconds` for slow nodes |
| Ingress has no address | AWS Load Balancer Controller installed? Subnets tagged `kubernetes.io/role/elb=1`? `kubectl describe ingress -n testcomp1` |
| 503/502 from ALB | Target group health check path `/health`; security groups allow ALB -> pod port 8080 |
| Redis errors | Security group of ElastiCache must allow the EKS node/pod security group on 6379 |

## 10. Security considerations

- Container runs as non-root user `app` (uid 1001).
- Weather API key is stored in a Kubernetes Secret, not in the manifest. Consider AWS Secrets Manager + External Secrets.
- Add TLS to the ALB with an ACM certificate (`alb.ingress.kubernetes.io/certificate-arn`, listen-ports 443).
- Restrict network access with NetworkPolicies and security groups; use IRSA instead of static AWS keys.
- Several dependencies in `pom.xml` are old and have known CVEs (log4j-core 2.14.1, jackson-databind 2.9.10, commons-collections 3.2.1, spring 5.3.17). Upgrade them.

## 11. Java / Tomcat notes

- The WAR was designed for a full Java EE server (Liberty). The image uses Tomcat 9, which provides the Servlet/JSP APIs only. `@Inject` in `WeatherServlet` and `@Stateless` on `ModResortsCustomerInformation` are not processed by Tomcat. If `customerInfo` is needed at runtime, add CDI (Weld) or switch the runtime to TomEE/Liberty, or instantiate the class explicitly.
- `ibm-web-ext.xml` context root `/resorts` is ignored; the app is served at `/`.
- JVM is container aware (`-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0`); with a 1Gi limit the heap is about 768 MB.
- Tomcat is started with `catalina.sh run` so SIGTERM triggers graceful shutdown (`terminationGracePeriodSeconds: 30`).
