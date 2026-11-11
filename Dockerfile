# ---- Stage 1: strip unused CSS with PurgeCSS ----
FROM node:18-alpine AS css-build
WORKDIR /build
RUN npm install -g purgecss@5
COPY WebContent ./WebContent
COPY purgecss.config.js ./
RUN purgecss --config ./purgecss.config.js

# ---- Stage 2: build the application ----
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace
# Copy build descriptor first for dependency layer caching
COPY pom.xml ./
RUN mvn -B dependency:go-offline
COPY src ./src
COPY WebContent ./WebContent
# Replace the original stylesheet with the purged one
COPY --from=css-build /build/build/purged-css/styles.css ./WebContent/styles.css
RUN mvn -B clean package -DskipTests

# ---- Stage 3: minimal runtime image ----
FROM eclipse-temurin:8-jre
ENV TZ=UTC \
    LANG=C.UTF-8 \
    SERVER_PORT=8080 \
    SPRING_PROFILES_ACTIVE=docker \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Xms256m -Dfile.encoding=UTF-8 -Djava.security.egd=file:/dev/./urandom"
WORKDIR /app
RUN groupadd -r appgroup && useradd -r -g appgroup -m -d /home/appuser appuser
COPY --from=builder --chown=appuser:appgroup /workspace/target/modresorts-*.war /app/app.war
USER appuser
EXPOSE 8080
# exec form via sh so JAVA_OPTS expands and java receives signals (PID 1) for graceful shutdown
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.war"]
