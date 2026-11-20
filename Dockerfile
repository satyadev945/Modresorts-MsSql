# ---------- Stage 1: strip unused CSS with PurgeCSS ----------
FROM node:20-alpine AS css-purge
WORKDIR /build
RUN npm install -g purgecss@6
COPY WebContent/ WebContent/
COPY purgecss.config.js .
RUN purgecss --config purgecss.config.js

# ---------- Stage 2: build the application ----------
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -B -q dependency:go-offline
COPY src/ src/
COPY WebContent/ WebContent/
# Replace original stylesheet with the purged one
COPY --from=css-purge /build/purged-css/styles.css WebContent/styles.css
RUN mvn -B -q package -DskipTests

# ---------- Stage 3: minimal runtime image ----------
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY --from=build /app/target/modresorts-*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java","-jar","/app/app.jar"]
