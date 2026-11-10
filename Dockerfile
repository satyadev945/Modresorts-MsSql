# ---------- Stage 1: build the WAR ----------
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace

# Cache dependencies first
COPY pom.xml .
RUN mvn -B dependency:go-offline || true

# Copy sources and build
COPY src ./src
COPY WebContent ./WebContent
RUN mvn -B clean package -DskipTests

# ---------- Stage 2: Servlet container distribution (copied only, not run) ----------
FROM tomcat:8.5-jre8-temurin AS tomcat

# ---------- Stage 3: runtime ----------
FROM eclipse-temurin:8-jre

ENV TZ=UTC \
    LANG=C.UTF-8 \
    CATALINA_HOME=/usr/local/tomcat \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Xms256m -Dfile.encoding=UTF-8 -Duser.timezone=UTC -Djava.security.egd=file:/dev/./urandom" \
    ENABLE_JMX_APPINFO=false \
    WEATHER_API_KEY=""
ENV PATH="${CATALINA_HOME}/bin:${PATH}"

# Non-root user (numeric UID so Kubernetes runAsNonRoot can be verified)
RUN groupadd -r -g 1001 appgroup && useradd -r -u 1001 -g appgroup -d /usr/local/tomcat -s /sbin/nologin appuser

# Tomcat 8.5 (Servlet 3.1 - matches javaee-api 7.0 used by the application)
COPY --from=tomcat --chown=1001:1001 /usr/local/tomcat /usr/local/tomcat

WORKDIR /usr/local/tomcat

# Deploy the application as the root context
RUN rm -rf /usr/local/tomcat/webapps/*
COPY --from=builder --chown=1001:1001 /workspace/target/modresorts-*.war /usr/local/tomcat/webapps/ROOT.war

USER 1001:1001
EXPOSE 8080

# catalina.sh run keeps Tomcat in the foreground and handles SIGTERM for graceful shutdown
CMD ["catalina.sh", "run"]
