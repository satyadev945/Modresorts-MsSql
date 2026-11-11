# ---------- Stage 1: build the WAR ----------
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace

# Cache dependencies: copy the POM first
COPY pom.xml .
RUN mvn -B -q dependency:resolve

# Copy sources and web content (WebContent is the WAR source directory)
COPY src ./src
COPY WebContent ./WebContent
RUN mvn -B clean package -DskipTests

# ---------- Stage 2: Tomcat 9 (javax.servlet) distribution donor ----------
FROM tomcat:9.0-jdk8-temurin AS tomcat

# ---------- Stage 3: runtime on the requested base image ----------
FROM openjdk:8-jdk

ENV CATALINA_HOME=/opt/tomcat \
    CATALINA_BASE=/opt/tomcat \
    TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Xms256m -Dfile.encoding=UTF-8 -Duser.timezone=UTC -Djava.security.egd=file:/dev/./urandom"

# Servlet container (the application is a Java EE/Servlet WAR, not an executable JAR)
COPY --from=tomcat /usr/local/tomcat /opt/tomcat

# Non-root user, clean default webapps, root redirect to the /resorts context
RUN groupadd -r -g 1001 app \
    && useradd -r -u 1001 -g app -m -d /home/app app \
    && rm -rf /opt/tomcat/webapps/* \
    && mkdir -p /opt/tomcat/webapps/ROOT \
    && echo '<!DOCTYPE html><html><head><meta http-equiv="refresh" content="0; url=/resorts/"></head><body></body></html>' > /opt/tomcat/webapps/ROOT/index.html

# Context root /resorts (matches ibm-web-ext.xml and the paths used by main.js)
COPY --from=builder /workspace/target/*.war /opt/tomcat/webapps/resorts.war

RUN chown -R app:app /opt/tomcat /home/app

USER app
WORKDIR /opt/tomcat

EXPOSE 8080

# Environment used by the application (set at deploy time):
#   WEATHER_API_KEY, WEATHER_GRPC_TARGET, SERVER_NAME

# catalina.sh run keeps Tomcat in the foreground and handles SIGTERM for graceful shutdown
CMD ["/opt/tomcat/bin/catalina.sh", "run"]
