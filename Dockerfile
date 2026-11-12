# syntax=docker/dockerfile:1
# Multi-stage build: PurgeCSS -> Maven -> JDK 8 runtime (build with Docker, deploy to Azure AKS)

# ---- Stage 1: remove unused CSS rules with PurgeCSS ----
FROM node:20-alpine AS css-purge
WORKDIR /app
RUN npm install -g purgecss@6
COPY WebContent ./WebContent
COPY purgecss.config.js ./
RUN purgecss --config purgecss.config.js \
 && cp build/purged-css/styles.css WebContent/styles.css

# ---- Stage 2: build the application using the purged CSS ----
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace
# Copy pom.xml first to cache dependencies
COPY pom.xml ./
RUN mvn -B dependency:go-offline
# Copy sources
COPY src ./src
COPY WebContent ./WebContent
COPY --from=css-purge /app/WebContent/styles.css ./WebContent/styles.css
RUN mvn -B clean package -DskipTests

# ---- Stage 3: runtime image ----
FROM eclipse-temurin:8-jdk-alpine
WORKDIR /app

RUN addgroup -S -g 1001 appgroup && adduser -S -u 1001 -G appgroup -h /home/appuser appuser \
 && mkdir -p /home/appuser /app/logs \
 && chown -R appuser:appgroup /home/appuser /app

COPY --from=builder --chown=appuser:appgroup /workspace/target/modresorts-*.jar /app/app.jar

ENV SERVER_PORT=8080 \
    SPRING_PROFILES_ACTIVE=docker \
    TZ=UTC \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Duser.timezone=UTC -Dfile.encoding=UTF-8 -Djava.security.egd=file:/dev/./urandom"

USER appuser
EXPOSE 8080

# exec so that the JVM receives SIGTERM for graceful shutdown
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar --server.port=${SERVER_PORT}"]
