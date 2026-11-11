# ---------- Builder stage ----------
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace

# Cache dependencies first
COPY pom.xml .
RUN mvn -B dependency:resolve || true

# Copy sources and build
COPY src ./src
COPY WebContent ./WebContent
RUN mvn -B clean package -DskipTests

# ---------- Runtime stage ----------
FROM eclipse-temurin:8-jdk
ENV TZ=UTC \
    LANG=C.UTF-8 \
    SPRING_PROFILES_ACTIVE=docker \
    SERVER_PORT=8080 \
    JAVA_OPTS="-Xms256m -Xmx512m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Dfile.encoding=UTF-8 -Djava.security.egd=file:/dev/./urandom"

RUN groupadd -r -g 1001 appgroup && useradd -r -u 1001 -g appgroup -m -d /home/appuser appuser

WORKDIR /app
COPY --from=builder /workspace/target/modresorts-*.war /app/app.war
RUN chown -R appuser:appgroup /app

USER appuser
EXPOSE 8080

# exec form with sh so JAVA_OPTS expands; exec gives java PID 1 for graceful shutdown
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.war"]
