# ---------- Builder stage ----------
FROM maven:3.9.4-eclipse-temurin-8 AS builder

WORKDIR /workspace

# Copy pom first for dependency caching
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copy sources and build
COPY src ./src
COPY WebContent ./WebContent
RUN mvn clean package -DskipTests -B

# ---------- Runtime stage ----------
FROM eclipse-temurin:8-jdk-alpine

ENV TZ=UTC \
    LANG=C.UTF-8 \
    SERVER_PORT=8080 \
    SPRING_PROFILES_ACTIVE=docker \
    JAVA_OPTS="-Xms256m -Xmx512m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Dfile.encoding=UTF-8 -Djava.security.egd=file:/dev/urandom"

# Non-root user (home dir is used by the app for exporting reservations.zip)
RUN addgroup -S appgroup && adduser -S -G appgroup -h /home/appuser appuser

WORKDIR /app

COPY --from=builder /workspace/target/modresorts-2.0.0.jar /app/app.jar
RUN chown -R appuser:appgroup /app /home/appuser

USER appuser

EXPOSE 8080

# exec form via sh so that JAVA_OPTS expand and java receives SIGTERM (PID 1) for graceful shutdown
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
