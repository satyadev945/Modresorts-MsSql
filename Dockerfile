# ---------- Stage 1: build the WAR ----------
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace

# Cache dependencies first
COPY pom.xml .
RUN mvn -B dependency:go-offline || true

# Copy sources and build
COPY src ./src
COPY WebContent ./WebContent
RUN mvn -B clean package -DskipTests

# ---------- Stage 2: servlet container (Tomcat 9, javax.* namespace, Java 8) ----------
FROM tomcat:9.0-jdk8-temurin AS tomcat

# ---------- Stage 3: runtime ----------
FROM eclipse-temurin:8-jdk-alpine

ENV TZ=UTC \
    CATALINA_HOME=/usr/local/tomcat \
    CATALINA_BASE=/usr/local/tomcat \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Xms256m -Dfile.encoding=UTF-8 -Duser.timezone=UTC -Djava.security.egd=file:/dev/./urandom" \
    PATH="/usr/local/tomcat/bin:${PATH}"

# Non-root user
RUN addgroup -S app && adduser -S -G app -h /home/app app

# Tomcat distribution (pure Java) copied from the official image
COPY --from=tomcat --chown=app:app /usr/local/tomcat /usr/local/tomcat

WORKDIR /usr/local/tomcat
RUN rm -rf /usr/local/tomcat/webapps/* && mkdir -p /home/app && chown -R app:app /home/app

# Deploy the application as the ROOT context
COPY --from=builder --chown=app:app /workspace/target/*.war /usr/local/tomcat/webapps/ROOT.war

USER app
EXPOSE 8080

# catalina.sh run keeps Tomcat in the foreground (exec) so SIGTERM triggers graceful shutdown
CMD ["catalina.sh", "run"]
