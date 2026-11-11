# syntax=docker/dockerfile:1

# ---- Stage 1: remove unused CSS rules with PurgeCSS ----
FROM node:20-alpine AS css-optimizer
WORKDIR /build
RUN npm install --no-save --no-audit --no-fund purgecss@6
COPY WebContent ./WebContent
COPY purgecss.config.js ./
RUN npx purgecss --config purgecss.config.js

# ---- Stage 2: build the application using the purged static assets ----
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml ./
RUN mvn -B -q dependency:go-offline
COPY src ./src
COPY WebContent ./WebContent
COPY --from=css-optimizer /build/WebContent/styles.css ./WebContent/styles.css
RUN mvn -B -q package -DskipTests

# ---- Stage 3: minimal runtime image ----
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY --from=build /app/target/modresorts-*.jar /app/app.jar
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=30s CMD wget -qO- http://localhost:8080/health || exit 1
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
