# ---------- Build stage ----------
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace

# Cache dependencies: copy pom first
COPY pom.xml .
RUN mvn -B dependency:resolve

# Copy sources and static web content (packaged into META-INF/resources)
COPY src ./src
COPY WebContent ./WebContent
RUN mvn -B clean package -DskipTests

# ---------- Runtime stage ----------
FROM amazoncorretto:8

ENV TZ=UTC \
    LANG=C.UTF-8 \
    SPRING_PROFILES_ACTIVE=docker \
    SERVER_PORT=8080 \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Xms256m -Dfile.encoding=UTF-8 -Duser.timezone=UTC -Djava.security.egd=file:/dev/./urandom"

WORKDIR /app
COPY --from=builder --chown=1001:0 /workspace/target/modresorts-2.0.0.jar /app/app.jar

# Run as non-root (numeric UID, no package manager needed)
USER 1001

EXPOSE 8080

# exec form via sh so JAVA_OPTS expand and java receives signals (PID 1) for graceful shutdown
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
