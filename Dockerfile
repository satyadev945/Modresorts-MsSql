# ---------- Stage 1: strip unused CSS with PurgeCSS ----------
FROM node:18-alpine AS css-build
WORKDIR /app
COPY package.json purgecss.config.js ./
RUN npm install --no-audit --no-fund
COPY WebContent ./WebContent
RUN npm run purgecss

# ---------- Stage 2: build the WAR using purged CSS ----------
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace
# Copy pom.xml first for dependency caching
COPY pom.xml .
RUN mvn -B -q dependency:go-offline
COPY src ./src
COPY WebContent ./WebContent
# Replace original CSS with purged versions
COPY --from=css-build /app/purged-css/styles.css ./WebContent/styles.css
COPY --from=css-build /app/purged-css/pikaday.css ./WebContent/pikaday.css
RUN mvn -B -q clean package -DskipTests

# ---------- Stage 3: prepare Servlet container (Apache Tomcat 9, Java EE 7 / Servlet 3.1 compatible) ----------
FROM tomcat:9.0-jre8-temurin AS tomcat-dist
RUN rm -rf /usr/local/tomcat/webapps/* /usr/local/tomcat/webapps.dist \
    && mkdir -p /usr/local/tomcat/logs /usr/local/tomcat/temp /usr/local/tomcat/work \
    && sed -i 's|<Connector port="8080"|<Connector port="8080" server=" "|' /usr/local/tomcat/conf/server.xml

# ---------- Stage 4: runtime image ----------
FROM eclipse-temurin:8-jre

ENV TZ=UTC \
    LANG=C.UTF-8 \
    CATALINA_HOME=/opt/tomcat \
    CATALINA_BASE=/opt/tomcat \
    SERVER_PORT=8080 \
    JAVA_OPTS="-Xms256m -Xmx512m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Dfile.encoding=UTF-8 -Duser.timezone=UTC -Djava.security.egd=file:/dev/./urandom"

WORKDIR /opt/tomcat

# Tomcat distribution + application as ROOT context (context root "/")
COPY --from=tomcat-dist --chown=1001:0 /usr/local/tomcat /opt/tomcat
COPY --from=builder --chown=1001:0 /workspace/target/modresorts-*.war /opt/tomcat/webapps/ROOT.war

# Non-root user (UID 1001) with writable home and Tomcat directories
RUN mkdir -p /home/app && chown 1001:0 /home/app \
    && chmod -R g=u /opt/tomcat /home/app

ENV HOME=/home/app
USER 1001

EXPOSE 8080

# catalina.sh run keeps Tomcat in the foreground and forwards SIGTERM for graceful shutdown
CMD ["sh", "-c", "exec /opt/tomcat/bin/catalina.sh run"]
