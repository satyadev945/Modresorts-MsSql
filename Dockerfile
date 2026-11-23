# Stage 1: strip unused CSS with PurgeCSS (cz-css-1005)
FROM node:20-alpine AS css-purge
WORKDIR /build
RUN npm install -g purgecss@5
COPY WebContent ./WebContent
COPY purgecss.config.js ./purgecss.config.js
RUN purgecss --config ./purgecss.config.js

# Stage 2: build the WAR using the purged CSS
FROM maven:3.9-eclipse-temurin-8 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -B -q dependency:go-offline || true
COPY src ./src
COPY WebContent ./WebContent
COPY --from=css-purge /build/WebContent/styles.css ./WebContent/styles.css
COPY --from=css-purge /build/WebContent/pikaday.css ./WebContent/pikaday.css
RUN mvn -B -q package -DskipTests

# Stage 3: minimal production image
FROM openliberty/open-liberty:full-java8-openj9-ubi
COPY --from=build /app/target/modresorts-2.0.0.war /config/dropins/modresorts.war
EXPOSE 9080
HEALTHCHECK CMD curl -f http://localhost:9080/modresorts/health || exit 1
