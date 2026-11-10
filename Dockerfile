# ---------------------------------------------------------------------------
# ModResorts (WAR, Java EE 7 / Servlet 3.1 / CDI / EJB Lite, Java 8)
#
# Stage 1: build the WAR with Maven (system mvn, no wrapper)
# Stage 2: source of the Open Liberty runtime (Java EE 7 application server)
# Stage 3: runtime on eclipse-temurin:8-jdk (explicit base image)
# ---------------------------------------------------------------------------
ARG LIBERTY_IMAGE=icr.io/appcafe/open-liberty:full-java8-openj9-ubi

# ---------- Stage 1: builder ----------
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace

# Cache dependencies: copy the build descriptor first
COPY pom.xml .
RUN mvn -B -q dependency:resolve || true

# Copy sources and build the WAR
COPY . .
RUN mvn -B clean package -DskipTests

# ---------- Stage 2: Open Liberty distribution (Java EE 7 server) ----------
FROM ${LIBERTY_IMAGE} AS liberty

# ---------- Stage 3: runtime ----------
FROM eclipse-temurin:8-jdk

ENV TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    WLP_HOME=/opt/ol/wlp \
    SERVER_NAME_LIBERTY=defaultServer \
    ENABLE_JMX_APPINFO=true \
    WEATHER_API_KEY="" \
    JVM_ARGS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Xms256m -Dfile.encoding=UTF-8 -Duser.timezone=UTC -Djava.security.egd=file:/dev/./urandom"

# Non-root user (uid 1001, group 0 so OpenShift/AKS arbitrary-uid policies work)
RUN groupadd -g 1001 appgroup \
    && useradd -u 1001 -g 0 -G appgroup -m -d /home/appuser -s /sbin/nologin appuser

# Liberty runtime from the Liberty stage
COPY --from=liberty --chown=1001:0 /opt/ol /opt/ol

# Server configuration and application
COPY --chown=1001:0 docker/server.xml /opt/ol/wlp/usr/servers/defaultServer/server.xml
COPY --from=builder --chown=1001:0 /workspace/target/*.war /opt/ol/wlp/usr/servers/defaultServer/apps/modresorts.war

RUN chmod -R g=u /opt/ol/wlp/usr /home/appuser

USER 1001
WORKDIR /opt/ol/wlp/usr/servers/defaultServer

EXPOSE 9080

# Liberty handles SIGTERM for graceful shutdown
ENTRYPOINT ["/opt/ol/wlp/bin/server", "run", "defaultServer"]
