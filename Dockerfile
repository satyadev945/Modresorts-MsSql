# ---- Stage 1: strip unused CSS with PurgeCSS ----
FROM node:18-alpine AS css-build
WORKDIR /build
RUN npm install -g purgecss@5
COPY WebContent ./WebContent
COPY purgecss.config.js ./
RUN purgecss --config ./purgecss.config.js

# ---- Stage 2: build the application ----
FROM maven:3.9-eclipse-temurin-8 AS build
WORKDIR /app
COPY pom.xml ./
COPY src ./src
COPY WebContent ./WebContent
# Replace the original stylesheet with the purged one
COPY --from=css-build /build/build/purged-css/styles.css ./WebContent/styles.css
RUN mvn -B -q package -DskipTests

# ---- Stage 3: minimal runtime image ----
FROM eclipse-temurin:8-jre
WORKDIR /app
COPY --from=build /app/target/modresorts-*.war /app/app.war
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.war"]
