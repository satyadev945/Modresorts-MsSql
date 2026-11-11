# syntax=docker/dockerfile:1

# ---- Stage 1: strip unused CSS with PurgeCSS ----
FROM node:18-alpine AS css-purge
WORKDIR /build
RUN npm install -g purgecss@5
COPY purgecss.config.js ./
COPY WebContent ./WebContent
RUN purgecss --config purgecss.config.js

# ---- Stage 2: build the WAR ----
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace
COPY pom.xml ./
RUN mvn -B dependency:go-offline || true
COPY src ./src
COPY WebContent ./WebContent
# Replace the original stylesheet with the purged one
COPY --from=css-purge /build/purged-css/styles.css ./WebContent/styles.css
RUN mvn -B clean package -DskipTests

# ---- Stage 3: Tomcat distribution (source of the servlet container only) ----
FROM tomcat:9.0-jdk8-temurin AS tomcat

# ---- Stage 4: runtime image ----
FROM eclipse-temurin:8-jdk

ENV CATALINA_HOME=/opt/tomcat \
    TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Xms256m -Dfile.encoding=UTF-8 -Duser.timezone=UTC -Djava.security.egd=file:/dev/urandom"

# Servlet container (copied from the official Tomcat image, no package manager needed)
COPY --from=tomcat /usr/local/tomcat /opt/tomcat

RUN rm -rf /opt/tomcat/webapps/* \
    && groupadd -r appuser \
    && useradd -r -g appuser -d /opt/tomcat -s /sbin/nologin appuser

COPY --from=builder /workspace/target/modresorts-2.0.0.war /opt/tomcat/webapps/ROOT.war

RUN chown -R appuser:appuser /opt/tomcat

USER appuser
WORKDIR /opt/tomcat

EXPOSE 8080

# Graceful shutdown: catalina.sh run keeps Tomcat in foreground and handles SIGTERM
CMD ["/opt/tomcat/bin/catalina.sh", "run"]
