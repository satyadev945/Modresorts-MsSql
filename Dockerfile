# ---- Stage 1: strip unused CSS with PurgeCSS ----
FROM node:20-alpine AS css-purge
WORKDIR /build
RUN npm install --global purgecss@5
COPY WebContent ./WebContent
COPY purgecss.config.js ./purgecss.config.js
RUN purgecss --config ./purgecss.config.js \
    && cp purged-css/styles.css WebContent/styles.css

# ---- Stage 2: build the WAR using purged CSS and fetch the embedded servlet container ----
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace
COPY pom.xml .
RUN mvn -B dependency:resolve || true
COPY src ./src
COPY WebContent ./WebContent
COPY --from=css-purge /build/WebContent/styles.css ./WebContent/styles.css
RUN mvn -B clean package -DskipTests
# Embedded Tomcat 9 (javax.* namespace, Servlet 3.1+/JSP) used to run the WAR on a plain JRE
RUN mvn -B dependency:copy \
      -Dartifact=com.heroku:webapp-runner:9.0.80.0 \
      -DoutputDirectory=/workspace/runner \
      -Dmdep.stripVersion=true

# ---- Stage 3: minimal runtime image ----
FROM eclipse-temurin:8-jre
ENV TZ=UTC \
    LANG=C.UTF-8 \
    APP_PORT=9080 \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Dfile.encoding=UTF-8 -Djava.security.egd=file:/dev/urandom"
WORKDIR /app
RUN groupadd -r -g 1001 appgroup && useradd -r -u 1001 -g appgroup -d /app -s /sbin/nologin appuser
COPY --from=builder --chown=1001:1001 /workspace/runner/webapp-runner.jar /app/webapp-runner.jar
COPY --from=builder --chown=1001:1001 /workspace/target/modresorts-2.0.0.war /app/modresorts.war
USER 1001
EXPOSE 9080
# exec form via sh so JAVA_OPTS expands while java stays PID 1 (graceful SIGTERM shutdown)
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/webapp-runner.jar --port ${APP_PORT} /app/modresorts.war"]
