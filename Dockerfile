# Stage 1: strip unused CSS with PurgeCSS
FROM node:18-alpine AS css-purge
WORKDIR /build
COPY package.json purgecss.config.js ./
RUN npm install --no-audit --no-fund
COPY WebContent ./WebContent
RUN npx purgecss --config purgecss.config.js

# Stage 2: build the WAR using the purged CSS
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace
COPY pom.xml .
RUN mvn -B dependency:go-offline
COPY src ./src
COPY WebContent ./WebContent
COPY --from=css-purge /build/WebContent/styles.css ./WebContent/styles.css
RUN mvn -B clean package -DskipTests

# Stage 3: servlet container source (only used to copy Tomcat binaries)
FROM tomcat:9.0-jre8-temurin AS tomcat

# Stage 4: runtime image (explicit base image: eclipse-temurin:8-jre)
FROM eclipse-temurin:8-jre

ENV TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    CATALINA_HOME=/usr/local/tomcat \
    CATALINA_BASE=/usr/local/tomcat \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Xms256m -Dfile.encoding=UTF-8 -Duser.timezone=UTC -Djava.security.egd=file:/dev/./urandom" \
    PATH=/usr/local/tomcat/bin:$PATH

# Tomcat 9 runtime (the application is a WAR and needs a servlet container)
COPY --from=tomcat /usr/local/tomcat /usr/local/tomcat
RUN rm -rf /usr/local/tomcat/webapps/* \
    && groupadd --system --gid 1001 appgroup \
    && useradd --system --uid 1001 --gid appgroup --home-dir /usr/local/tomcat --shell /usr/sbin/nologin appuser \
    && chown -R appuser:appgroup /usr/local/tomcat

COPY --from=builder --chown=appuser:appgroup /workspace/target/*.war /usr/local/tomcat/webapps/ROOT.war

WORKDIR /usr/local/tomcat
USER appuser

EXPOSE 8080

# Application configuration (provided at runtime)
ENV WEATHER_API_KEY="" \
    WEATHER_SERVICE_URL=""

# catalina.sh run keeps Tomcat in the foreground and forwards SIGTERM for graceful shutdown
CMD ["catalina.sh", "run"]
