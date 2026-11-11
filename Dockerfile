# syntax=docker/dockerfile:1

# ---- Stage 1: strip unused CSS with PurgeCSS ----
FROM node:18-alpine AS css-purge
WORKDIR /build
RUN npm install -g purgecss@5
COPY purgecss.config.js ./
COPY WebContent ./WebContent
RUN purgecss --config purgecss.config.js

# ---- Stage 2: build the WAR ----
FROM maven:3.9-eclipse-temurin-8 AS build
WORKDIR /app
COPY pom.xml ./
RUN mvn -B -q dependency:go-offline || true
COPY src ./src
COPY WebContent ./WebContent
# Replace the original stylesheet with the purged one
COPY --from=css-purge /build/purged-css/styles.css ./WebContent/styles.css
RUN mvn -B -q package -DskipTests

# ---- Stage 3: minimal runtime image ----
FROM tomcat:9.0-jdk8-temurin
RUN rm -rf /usr/local/tomcat/webapps/*
COPY --from=build /app/target/modresorts-2.0.0.war /usr/local/tomcat/webapps/ROOT.war
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fs http://localhost:8080/health || exit 1
CMD ["catalina.sh", "run"]
