# syntax=docker/dockerfile:1

# ---- Stage 1: purge unused CSS (cz-css-1005) ----
FROM node:20-alpine AS css-purge
WORKDIR /web
COPY WebContent/ ./WebContent/
RUN npm install -g purgecss@6 \
 && mkdir -p /web/purged \
 && purgecss \
      --css WebContent/styles.css \
      --content "WebContent/**/*.html" "WebContent/**/*.jsp" "WebContent/**/*.js" \
      --safelist bold \
      --output /web/purged/

# ---- Stage 2: build the application ----
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace
# Copy pom.xml first for dependency layer caching
COPY pom.xml ./
RUN mvn -B dependency:go-offline
COPY src ./src
COPY WebContent ./WebContent
# Replace the original stylesheet with the purged one
COPY --from=css-purge /web/purged/styles.css ./WebContent/styles.css
RUN mvn -B clean package -DskipTests

# ---- Stage 3: runtime image (explicit base image) ----
FROM eclipse-temurin:8-jdk
ENV TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    SPRING_PROFILES_ACTIVE=docker \
    PORT=9080 \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Xms256m -Dfile.encoding=UTF-8 -Djava.security.egd=file:/dev/./urandom"

RUN groupadd --system --gid 1001 appgroup \
 && useradd --system --uid 1001 --gid appgroup --create-home --home-dir /home/appuser --shell /usr/sbin/nologin appuser \
 && mkdir -p /app \
 && chown -R appuser:appgroup /app /home/appuser

WORKDIR /app
COPY --from=builder --chown=appuser:appgroup /workspace/target/modresorts-*.jar /app/app.jar

USER appuser
EXPOSE 9080

# exec so the JVM receives SIGTERM for graceful shutdown
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
