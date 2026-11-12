# ---------- Build stage ----------
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace

# Copy the POM first to leverage Docker layer caching for dependencies
COPY pom.xml .
RUN mvn -B -q dependency:resolve

# Copy sources and web content, then build
COPY src ./src
COPY WebContent ./WebContent
RUN mvn -B clean package -DskipTests

# ---------- Runtime stage ----------
FROM eclipse-temurin:8-jre

ENV TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    SPRING_PROFILES_ACTIVE=docker \
    SERVER_PORT=8080 \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Xms256m -Dfile.encoding=UTF-8 -Djava.security.egd=file:/dev/./urandom"

WORKDIR /app

# Non-root user
RUN groupadd --system --gid 1001 appgroup \
    && useradd --system --uid 1001 --gid appgroup --home-dir /app --shell /usr/sbin/nologin appuser

COPY --from=builder --chown=appuser:appgroup /workspace/target/*.jar /app/app.jar

USER appuser

EXPOSE 8080

# exec form via sh so JAVA_OPTS is expanded and the JVM receives SIGTERM (graceful shutdown)
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
