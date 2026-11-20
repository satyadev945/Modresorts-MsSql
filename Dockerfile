# ---------- Stage 1: build the application ----------
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace

# Cache dependencies: copy the POM first
COPY pom.xml .
RUN mvn -B -q dependency:go-offline

# Copy sources and static web content (WebContent is packaged as META-INF/resources)
COPY src/ src/
COPY WebContent/ WebContent/
RUN mvn -B clean package -DskipTests

# ---------- Stage 2: runtime image ----------
FROM eclipse-temurin:8-jre
WORKDIR /app

ENV TZ=UTC \
    LANG=C.UTF-8 \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Dfile.encoding=UTF-8 -Djava.security.egd=file:/dev/./urandom" \
    SPRING_PROFILES_ACTIVE=docker \
    SERVER_PORT=8080

# Non-root user
RUN groupadd -r app && useradd -r -g app -d /app -s /usr/sbin/nologin app

COPY --from=builder /workspace/target/modresorts-*.jar /app/app.jar
RUN chown -R app:app /app

USER app
EXPOSE 8080

# exec so that the JVM receives SIGTERM for graceful shutdown
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
