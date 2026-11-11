# Stage 1: strip unused CSS with PurgeCSS
FROM node:18-alpine AS css-purge
WORKDIR /build
RUN npm install --no-save --no-audit --no-fund purgecss@5.0.0
COPY purgecss.config.js ./
COPY WebContent ./WebContent
RUN npx purgecss --config purgecss.config.js

# Stage 2: build the WAR using the purged stylesheet
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace
COPY pom.xml ./
RUN mvn -B -q dependency:resolve
COPY src ./src
COPY WebContent ./WebContent
COPY --from=css-purge /build/purged-css/styles.css ./WebContent/styles.css
RUN mvn -B -q clean package -DskipTests

# Stage 3: servlet container (Tomcat 9, javax.servlet) cleaned of default webapps
FROM tomcat:9.0-jdk8-temurin AS tomcat
RUN rm -rf /usr/local/tomcat/webapps/* /usr/local/tomcat/webapps.dist

# Stage 4: runtime image (explicit base image: eclipse-temurin:8-jre)
FROM eclipse-temurin:8-jre

ENV CATALINA_HOME=/usr/local/tomcat \
    TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    REDIS_HOST=localhost \
    REDIS_PORT=6379 \
    REDIS_CACHE_TTL=300 \
    CATALINA_OPTS="-Xms256m -Xmx512m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Dfile.encoding=UTF-8 -Duser.timezone=UTC -Djava.security.egd=file:/dev/./urandom"
ENV PATH="${CATALINA_HOME}/bin:${PATH}"

# Non-root user
RUN groupadd -r -g 1001 appgroup && useradd -r -u 1001 -g appgroup -d /usr/local/tomcat appuser

COPY --from=tomcat --chown=appuser:appgroup /usr/local/tomcat /usr/local/tomcat
COPY --from=builder --chown=appuser:appgroup /workspace/target/*.war /usr/local/tomcat/webapps/ROOT.war

WORKDIR /usr/local/tomcat
USER appuser

EXPOSE 8080

# catalina.sh run keeps Tomcat in the foreground and forwards SIGTERM for graceful shutdown
CMD ["catalina.sh", "run"]
