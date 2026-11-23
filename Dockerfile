# syntax=docker/dockerfile:1

# ---- Stage 1: purge unused CSS with PurgeCSS ----
FROM node:20-alpine AS css-purge
WORKDIR /build
RUN npm install --no-save --no-audit --no-fund purgecss@5.0.0
COPY WebContent/ ./WebContent/
RUN mkdir -p /build/purged && \
    npx purgecss \
      --css WebContent/styles.css \
      --content "WebContent/**/*.html" "WebContent/**/*.jsp" "WebContent/main.js" \
      --output /build/purged/

# ---- Stage 2: build the application with purged CSS ----
FROM maven:3.9-eclipse-temurin-8 AS build
WORKDIR /app
COPY pom.xml ./
RUN mvn -B -q dependency:go-offline || true
COPY src ./src
COPY WebContent ./WebContent
# Replace original stylesheet with the purged version
COPY --from=css-purge /build/purged/styles.css ./WebContent/styles.css
RUN mvn -B -q package -DskipTests

# ---- Stage 3: minimal runtime image ----
FROM eclipse-temurin:8-jre-alpine
WORKDIR /app
COPY --from=build /app/target/modresorts-2.0.0.war /app/app.war
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.war"]
