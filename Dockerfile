# Stage 1: purge unused CSS with PurgeCSS
FROM node:18-alpine AS css-purge
WORKDIR /build
RUN npm install -g purgecss@5
COPY WebContent ./WebContent
COPY purgecss.config.js ./purgecss.config.js
RUN purgecss --config ./purgecss.config.js

# Stage 2: build the WAR using the purged CSS
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace
# Copy pom.xml first to cache dependencies
COPY pom.xml .
RUN mvn -B dependency:go-offline
COPY src ./src
COPY WebContent ./WebContent
COPY --from=css-purge /build/purged/styles.css ./WebContent/styles.css
RUN mvn -B clean package -DskipTests

# Stage 3: Tomcat distribution (servlet container for the WAR; Servlet 3.1 / javax.* namespace)
FROM tomcat:9.0-jdk8-temurin AS tomcat-dist
RUN rm -rf /usr/local/tomcat/webapps/* /usr/local/tomcat/webapps.dist

# Stage 4: runtime image (explicit base image)
FROM eclipse-temurin:8-jdk-alpine

ENV TZ=UTC \
    LANG=C.UTF-8 \
    CATALINA_HOME=/usr/local/tomcat \
    CATALINA_BASE=/usr/local/tomcat \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Xms256m -Dfile.encoding=UTF-8 -Duser.timezone=UTC -Djava.security.egd=file:/dev/./urandom"

WORKDIR /usr/local/tomcat

COPY --from=tomcat-dist /usr/local/tomcat /usr/local/tomcat
COPY --from=builder /workspace/target/modresorts-2.0.0.war /usr/local/tomcat/webapps/ROOT.war

# Non-root user
RUN addgroup -S -g 1001 appgroup && adduser -S -u 1001 -G appgroup appuser \
    && chown -R appuser:appgroup /usr/local/tomcat \
    && chmod +x /usr/local/tomcat/bin/*.sh

USER appuser

EXPOSE 8080

# catalina.sh run: runs in foreground and forwards SIGTERM for graceful shutdown
CMD ["catalina.sh", "run"]
