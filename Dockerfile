# ---- Stage 1: build the WAR with Maven (system mvn, no wrapper) ----
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace
# Copy pom.xml first so dependency layers are cached
COPY pom.xml .
RUN mvn -B dependency:resolve || true
COPY src ./src
COPY WebContent ./WebContent
RUN mvn -B clean package -DskipTests \
    && mkdir -p /workspace/exploded \
    && cd /workspace/exploded \
    && jar xf /workspace/target/modresorts-2.0.0.war

# ---- Stage 2: purge unused CSS (PurgeCSS) ----
FROM node:20-alpine AS purgecss
WORKDIR /app
RUN npm install -g purgecss@6
COPY WebContent ./WebContent
COPY purgecss.config.js ./
RUN purgecss --config purgecss.config.js \
    && cp purged-css/styles.css WebContent/styles.css \
    && cp purged-css/pikaday.css WebContent/pikaday.css

# ---- Stage 3: source of the Servlet container (Apache Tomcat 9, javax.servlet) ----
FROM tomcat:9.0-jdk8-temurin AS tomcat

# ---- Stage 4: runtime image (explicit base image: eclipse-temurin:8-jre) ----
FROM eclipse-temurin:8-jre

ENV TZ=UTC \
    LANG=C.UTF-8 \
    CATALINA_HOME=/opt/tomcat \
    CATALINA_BASE=/opt/tomcat \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Dfile.encoding=UTF-8 -Duser.timezone=UTC -Djava.security.egd=file:/dev/./urandom" \
    REDIS_PORT=6379 \
    WEATHER_API_KEY_NAME=WEATHER_API_KEY

# Non-root user
RUN groupadd --system --gid 1001 app \
    && useradd --system --uid 1001 --gid app --create-home --home-dir /home/app app

# Tomcat runtime (copied from the official Tomcat image, no package manager used)
COPY --from=tomcat --chown=app:app /usr/local/tomcat /opt/tomcat

# Deploy application as ROOT context
RUN rm -rf /opt/tomcat/webapps/* \
    && mkdir -p /opt/tomcat/webapps/ROOT \
    && chown app:app /opt/tomcat/webapps/ROOT
COPY --from=builder --chown=app:app /workspace/exploded /opt/tomcat/webapps/ROOT
# Overlay the purged (minimal) CSS
COPY --from=purgecss --chown=app:app /app/WebContent/styles.css /opt/tomcat/webapps/ROOT/styles.css
COPY --from=purgecss --chown=app:app /app/WebContent/pikaday.css /opt/tomcat/webapps/ROOT/pikaday.css

WORKDIR /opt/tomcat
USER app

EXPOSE 8080

# catalina.sh run execs the JVM in the foreground so SIGTERM triggers a graceful Tomcat shutdown
CMD ["/opt/tomcat/bin/catalina.sh", "run"]
