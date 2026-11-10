# ModResorts – Deployment Guide (Docker & Azure AKS)

## 1. Application overview

| Item | Value |
|------|-------|
| Technology | Java EE 7 web application (Servlet 3.1, CDI, EJB Lite), Java 8 |
| Build tool | Maven (`mvn`, no wrapper) |
| Packaging | WAR (`target/modresorts-2.0.0.war`) |
| Runtime | Open Liberty (`javaee-7.0` feature) running on `eclipse-temurin:8-jdk` |
| HTTP port | 9080 (`docker/server.xml`) |
| Health endpoint | `GET /health` → `{"status":"UP"}` (`HealthServlet`) |
| Context root | `/` |

Environment variables read by the application:

| Variable | Purpose | Default |
|----------|---------|---------|
| `WEATHER_API_KEY` | Real-time weather provider key. If empty, built-in sample data is used | empty |
| `ENABLE_JMX_APPINFO` | Enable/disable JMX AppInfo MBean registration | `true` |
| `SERVER_NAME` | Name shown in UI (falls back to `HOSTNAME`) | pod name |
| `JVM_ARGS` | JVM options picked up by Liberty | container-aware, 75% RAM |

The application has no active database connection (the data source lookup is disabled for demo setup). `mssql-jdbc` is on the classpath; if you enable a database, supply connection settings through environment variables/secrets.

## 2. Prerequisites

- Docker 20.10+ (BuildKit recommended)
- Azure CLI 2.50+ (`az login` completed) and an Azure subscription
- kubectl 1.25+
- An Azure Container Registry (or Docker Hub account)
- An AKS cluster with the Application Gateway Ingress Controller (AGIC) add-on (or change the ingress class to `nginx`)

## 3. Local development with Docker Compose

```bash
export WEATHER_API_KEY=""            # optional
docker compose up --build
# open http://localhost:9080/ and http://localhost:9080/health
```

`docker-compose.yml` contains only the application service. Stop with `docker compose down`.

## 4. Build and push the image

Run from the repository root:

```bash
./scripts/build-push.sh        # Linux/macOS
scripts\build-push.bat         # Windows
```

The script prompts for an image tag (default `latest`; sanitized to lowercase), the registry type (1 = Azure ACR, 2 = Docker Hub) and registry credentials. For ACR it runs `az acr login --name <acr>`. The final image URI is printed.

Dockerfile stages:
1. `maven:3.9.4-eclipse-temurin-8` builds the WAR (`mvn clean package -DskipTests`; dependencies resolved first for layer caching).
2. `icr.io/appcafe/open-liberty:full-java8-openj9-ubi` (overridable via `--build-arg LIBERTY_IMAGE=...`) provides the Liberty server files.
3. `eclipse-temurin:8-jdk` (explicit base image) is the runtime; Liberty is copied in, the WAR is deployed, and the container runs as non-root UID 1001. No package manager is used in the runtime stage and there is no `HEALTHCHECK` (Kubernetes probes are used).

## 5. AKS setup

```bash
az group create -n <rg> -l <region>
az aks create -g <rg> -n <cluster> --node-count 2 --attach-acr <acr-name> \
  --enable-addons ingress-appgw --appgw-name <gw> --appgw-subnet-cidr 10.225.0.0/16 --generate-ssh-keys
az aks get-credentials -g <rg> -n <cluster>
kubectl get nodes
```

`--attach-acr` lets the cluster pull from ACR without image pull secrets. For Docker Hub private repos, create an `imagePullSecret`.

## 6. Deploy to AKS

```bash
./scripts/deploy-image.sh      # Linux/macOS
scripts\deploy-image.bat       # Windows
```

The script prompts for resource group, cluster name, image URI and the optional env vars (`WEATHER_API_KEY`, `ENABLE_JMX_APPINFO`, `SERVER_NAME`). It substitutes `{{IMAGE_URI}}` and the env placeholders in a temporary copy of the manifests, fetches credentials (`az aks get-credentials`), checks connectivity, applies manifests in order and waits for the rollout.

| Manifest | Description |
|----------|-------------|
| `kubernetes/namespace.yaml` | Namespace `modresorts` |
| `kubernetes/deployment.yaml` | 2 replicas, port 9080, requests 250m/512Mi, limits 500m/1Gi, startup/liveness/readiness probes on `/health` |
| `kubernetes/service.yaml` | ClusterIP `modresorts-service`, port 80 → 9080 |
| `kubernetes/ingress.yaml` | AGIC ingress, host `modresorts.example.com` (edit to your domain) |

Verify:

```bash
kubectl get pods,svc,ingress -n modresorts
kubectl logs deploy/modresorts -n modresorts
```

## 7. Scaling and management

```bash
kubectl scale deployment/modresorts -n modresorts --replicas=4
kubectl autoscale deployment/modresorts -n modresorts --cpu-percent=70 --min=2 --max=6
kubectl set image deployment/modresorts modresorts=<registry>/modresorts:<newtag> -n modresorts
kubectl rollout status deployment/modresorts -n modresorts
kubectl rollout undo deployment/modresorts -n modresorts      # rollback
```

The app keeps no state in the JVM that must be shared (sessions are local); use ingress session affinity or an external session store if sticky behaviour is needed.

## 8. Troubleshooting

| Symptom | Checks |
|---------|--------|
| `ImagePullBackOff` | Image URI/tag correct? `az aks update -g <rg> -n <cluster> --attach-acr <acr>`; `kubectl describe pod` |
| `CrashLoopBackOff` | `kubectl logs <pod> -n modresorts --previous`; check for OOMKilled and raise memory limit |
| Pod not Ready | Liberty startup takes ~20–40 s; check `/health` via `kubectl port-forward deploy/modresorts 9080:9080 -n modresorts` |
| Service unreachable | `kubectl get endpoints modresorts-service -n modresorts` must list pod IPs |
| Ingress has no address / 502 | Verify AGIC is installed (`kubectl get pods -n kube-system | grep ingress`), host header matches, backend health probe path `/health` |
| Liberty image tag not found at build | Pass another tag: `docker build --build-arg LIBERTY_IMAGE=<image> .` |

## 9. Configuration and security

- Do not commit secrets. For `WEATHER_API_KEY` in production, store it in a Kubernetes Secret and reference it with `secretKeyRef` instead of a literal value.
- The container runs as non-root (UID 1001) with no extra packages installed.
- Terminate TLS at the ingress (add `appgw.ingress.kubernetes.io/ssl-redirect: "true"` and a certificate/`tls` section).
- `log4j-core 2.14.1`, `jackson-databind 2.9.10`, `commons-collections 3.2.1` and `spring-webmvc 5.3.17` in `pom.xml` have known vulnerabilities; upgrade them before production.
- Application security constraints in `web.xml` are commented out for demo purposes.

## 10. Java-specific notes

- Heap is sized by `-XX:MaxRAMPercentage=75.0` against the container limit (1Gi) with `-Xms256m`.
- Timezone is `UTC`; encoding is UTF-8.
- Liberty handles `SIGTERM` for graceful shutdown (`terminationGracePeriodSeconds: 30`).
- The WAR relies on CDI (`@Inject`) and EJB (`@Stateless`), which is why a Java EE 7 server (Liberty) is used rather than a bare servlet container.
