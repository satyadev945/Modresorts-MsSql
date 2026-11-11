# Stage 1: strip unused CSS with PurgeCSS
FROM node:18-alpine AS css-purge
WORKDIR /build
RUN npm install --no-save --no-audit --no-fund purgecss@5.0.0
COPY purgecss.config.js ./
COPY WebContent ./WebContent
RUN npx purgecss --config purgecss.config.js

# Stage 2: build the WAR using the purged stylesheet
FROM maven:3.9-eclipse-temurin-8 AS build
WORKDIR /app
COPY pom.xml ./
COPY src ./src
COPY WebContent ./WebContent
COPY --from=css-purge /build/purged-css/styles.css ./WebContent/styles.css
RUN mvn -B -q package -DskipTests

# Stage 3: minimal runtime image
FROM tomcat:9.0-jdk8-temurin
RUN rm -rf /usr/local/tomcat/webapps/*
COPY --from=build /app/target/modresorts-2.0.0.war /usr/local/tomcat/webapps/ROOT.war
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s CMD curl -fs http://localhost:8080/health || exit 1
