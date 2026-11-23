# Stage 1: strip unused CSS with PurgeCSS (cz-css-1005)
FROM node:20-alpine AS css-purge
WORKDIR /build
RUN npm install -g purgecss@5
COPY WebContent ./WebContent
COPY purgecss.config.js ./purgecss.config.js
RUN purgecss --config ./purgecss.config.js

# Stage 2: build the WAR using the purged CSS and fetch an embedded servlet container
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace
COPY pom.xml .
RUN mvn -B -q dependency:go-offline || true
COPY src ./src
COPY WebContent ./WebContent
COPY --from=css-purge /build/WebContent/styles.css ./WebContent/styles.css
COPY --from=css-purge /build/WebContent/pikaday.css ./WebContent/pikaday.css
RUN mvn -B -q clean package -DskipTests
# Embedded Tomcat 9 launcher (javax.servlet 3.1 compatible) used to run the WAR on a plain JDK image
RUN mvn -B -q dependency:copy -Dartifact=com.heroku:webapp-runner:9.0.68.0 -DoutputDirectory=/workspace/runner -Dmdep.stripVersion=true

# Stage 3: runtime
FROM eclipse-temurin:8-jdk-alpine
WORKDIR /app

RUN addgroup -S appgroup && adduser -S appuser -G appgroup

COPY --from=builder /workspace/target/modresorts-2.0.0.war /app/app.war
COPY --from=builder /workspace/runner/webapp-runner.jar /app/webapp-runner.jar
RUN chown -R appuser:appgroup /app

ENV TZ=UTC \
    LANG=en_US.UTF-8 \
    PORT=9080 \
    REDIS_HOST=localhost \
    REDIS_PORT=6379 \
    REDIS_CACHE_TTL=300 \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Xms256m -Dfile.encoding=UTF-8 -Duser.timezone=UTC -Djava.security.egd=file:/dev/./urandom"

USER appuser
EXPOSE 9080

ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/webapp-runner.jar --port ${PORT} /app/app.war"]
