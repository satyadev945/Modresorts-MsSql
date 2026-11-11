# syntax=docker/dockerfile:1

# ---- Stage 1: remove unused CSS rules with PurgeCSS ----
FROM node:20-alpine AS css-optimizer
WORKDIR /build
RUN npm install --no-save --no-audit --no-fund purgecss@6
COPY WebContent ./WebContent
COPY purgecss.config.js ./
RUN npx purgecss --config purgecss.config.js

# ---- Stage 2: build the application (Java 8 source/target) ----
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace
COPY pom.xml ./
RUN mvn -B -q dependency:go-offline
COPY src ./src
COPY WebContent ./WebContent
COPY --from=css-optimizer /build/WebContent/styles.css ./WebContent/styles.css
RUN mvn -B clean package -DskipTests

# ---- Stage 3: runtime image ----
FROM eclipse-temurin:8-jre
WORKDIR /app

ENV TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    SPRING_PROFILES_ACTIVE=docker \
    SERVER_PORT=8080 \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Xms256m -Dfile.encoding=UTF-8 -Djava.security.egd=file:/dev/./urandom"

RUN groupadd -r -g 1001 appgroup && useradd -r -u 1001 -g appgroup -d /app -s /sbin/nologin appuser

COPY --from=builder --chown=appuser:appgroup /workspace/target/modresorts-*.jar /app/app.jar

USER appuser

EXPOSE 8080

# exec form via sh so JAVA_OPTS is expanded and java is PID 1 (graceful SIGTERM shutdown)
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
