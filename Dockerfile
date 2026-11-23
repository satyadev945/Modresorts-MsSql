# ---- Stage 1: strip unused CSS with PurgeCSS ----
FROM node:20-alpine AS css-purge
WORKDIR /build
RUN npm install -g purgecss@6
COPY purgecss.config.js ./
COPY WebContent ./WebContent
RUN purgecss --config purgecss.config.js

# ---- Stage 2: build the application ----
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace
# Copy pom.xml first for dependency layer caching
COPY pom.xml ./
RUN mvn -B dependency:go-offline
COPY src ./src
COPY WebContent ./WebContent
# Overwrite CSS with the purged versions
COPY --from=css-purge /build/purged-css/styles.css ./WebContent/styles.css
COPY --from=css-purge /build/purged-css/pikaday.css ./WebContent/pikaday.css
RUN mvn -B clean package -DskipTests

# ---- Stage 3: runtime image ----
FROM eclipse-temurin:8-jdk-alpine
WORKDIR /app

ENV TZ=UTC \
    LANG=C.UTF-8 \
    SERVER_PORT=8080 \
    SPRING_PROFILES_ACTIVE=docker \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Xms256m -Dfile.encoding=UTF-8 -Djava.security.egd=file:/dev/./urandom"

# Non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

COPY --from=builder --chown=appuser:appgroup /workspace/target/modresorts-2.0.0.war /app/app.war

USER appuser
EXPOSE 8080

# exec so the JVM receives SIGTERM for graceful shutdown
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.war"]
