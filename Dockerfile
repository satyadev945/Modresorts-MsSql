# syntax=docker/dockerfile:1

# ---- Stage 1: purge unused CSS (cz-css-1005) ----
FROM node:20-alpine AS css-purge
WORKDIR /web
COPY WebContent/ ./WebContent/
RUN npm install -g purgecss@6 \
 && mkdir -p /web/purged \
 && purgecss \
      --css WebContent/styles.css \
      --content "WebContent/**/*.html" "WebContent/**/*.jsp" "WebContent/**/*.js" \
      --safelist bold \
      --output /web/purged/

# ---- Stage 2: build the application ----
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml ./
RUN mvn -B -q dependency:go-offline
COPY src ./src
COPY WebContent ./WebContent
# Replace the original stylesheet with the purged one
COPY --from=css-purge /web/purged/styles.css ./WebContent/styles.css
RUN mvn -B -q package -DskipTests

# ---- Stage 3: minimal runtime image ----
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java","-jar","/app/app.jar"]
