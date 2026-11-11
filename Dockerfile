# ---------- Stage 1: build the WAR ----------
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace

# Cache dependencies: copy pom.xml first
COPY pom.xml .
RUN mvn -B dependency:resolve dependency:resolve-plugins

# Copy sources and build
COPY src ./src
COPY WebContent ./WebContent
RUN mvn -B clean package -DskipTests

# ---------- Stage 2: source Apache Tomcat 9 (javax.servlet, Java 8 compatible) ----------
FROM tomcat:9.0-jdk8-corretto AS tomcat

# ---------- Stage 3: runtime (explicit base image: amazoncorretto:8) ----------
FROM amazoncorretto:8

ENV CATALINA_HOME=/opt/tomcat \
    TZ=UTC \
    LANG=C.UTF-8 \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Djava.security.egd=file:/dev/./urandom -Duser.timezone=UTC -Dfile.encoding=UTF-8 -Duser.home=/home/app"

# Tomcat runtime (no package manager used)
COPY --from=tomcat --chown=1001:0 /usr/local/tomcat /opt/tomcat

# Remove default webapps, prepare writable dirs for non-root user (UID 1001)
RUN rm -rf /opt/tomcat/webapps/* \
    && mkdir -p /home/app \
    && chown -R 1001:0 /home/app /opt/tomcat \
    && chmod -R g=u /home/app /opt/tomcat

# Deploy the application as the root context
COPY --from=builder --chown=1001:0 /workspace/target/modresorts-*.war /opt/tomcat/webapps/ROOT.war

USER 1001
WORKDIR /opt/tomcat

EXPOSE 8080

# "run" keeps Tomcat in the foreground and handles SIGTERM for graceful shutdown
CMD ["/opt/tomcat/bin/catalina.sh", "run"]
