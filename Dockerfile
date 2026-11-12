# syntax=docker/dockerfile:1
# Multi-stage build: PurgeCSS -> Maven -> slim JRE runtime (push to ACR, deploy to AKS)

# ---- Stage 1: remove unused CSS rules with PurgeCSS ----
FROM node:20-alpine AS css-purge
WORKDIR /app
RUN npm install -g purgecss@6
COPY WebContent ./WebContent
COPY purgecss.config.js ./
RUN purgecss --config purgecss.config.js \
 && cp build/purged-css/styles.css WebContent/styles.css

# ---- Stage 2: build the application using the purged CSS ----
FROM maven:3.9-eclipse-temurin-8 AS build
WORKDIR /build
COPY pom.xml ./
COPY src ./src
COPY WebContent ./WebContent
COPY --from=css-purge /app/WebContent/styles.css ./WebContent/styles.css
RUN mvn -B -DskipTests package

# ---- Stage 3: minimal runtime image ----
FROM eclipse-temurin:8-jre-alpine
WORKDIR /app
COPY --from=build /build/target/modresorts-*.jar /app/app.jar
ENV SERVER_PORT=8080
EXPOSE 8080
ENTRYPOINT ["sh", "-c", "java -jar /app/app.jar --server.port=${SERVER_PORT}"]
