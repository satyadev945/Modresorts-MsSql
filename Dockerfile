# syntax=docker/dockerfile:1

# ---- Stage 1: purge unused CSS with PurgeCSS ----
FROM node:20-alpine AS css-purge
WORKDIR /build
RUN npm install --no-save --no-audit --no-fund purgecss@5.0.0
COPY WebContent/ ./WebContent/
RUN mkdir -p /build/purged && \
    npx purgecss \
      --css WebContent/styles.css \
      --content "WebContent/**/*.html" "WebContent/**/*.jsp" "WebContent/main.js" \
      --output /build/purged/

# ---- Stage 2: build the application with purged CSS ----
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /app
COPY pom.xml ./
RUN mvn -B -q dependency:go-offline || true
COPY src ./src
COPY WebContent ./WebContent
# Replace original stylesheet with the purged version
COPY --from=css-purge /build/purged/styles.css ./WebContent/styles.css
RUN mvn -B clean package -DskipTests

# ---- Stage 3: runtime image ----
FROM eclipse-temurin:8-jdk-alpine
ENV TZ=UTC \
    LANG=C.UTF-8 \
    SERVER_PORT=8080 \
    SPRING_PROFILES_ACTIVE=docker \
    ENABLE_JMX_MBEAN=false \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Xms256m -Dfile.encoding=UTF-8 -Duser.timezone=UTC -Djava.security.egd=file:/dev/./urandom"
WORKDIR /app
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=builder --chown=appuser:appgroup /app/target/modresorts-2.0.0.war /app/app.war
USER appuser
EXPOSE 8080
# exec form of sh -c so JAVA_OPTS expands and java receives SIGTERM for graceful shutdown
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.war"]
