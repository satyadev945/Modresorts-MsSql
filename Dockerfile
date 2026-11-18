# syntax=docker/dockerfile:1

# ---- Stage 1: strip unused CSS with PurgeCSS (cz-css-1005) ----
FROM node:18-alpine AS css-purge
WORKDIR /build
RUN npm install -g purgecss@5
COPY purgecss.config.js ./
COPY WebContent ./WebContent
RUN purgecss --config purgecss.config.js \
 && cp purged-css/styles.css WebContent/styles.css \
 && cp purged-css/pikaday.css WebContent/pikaday.css

# ---- Stage 2: build the WAR using the purged static assets ----
FROM maven:3.8-openjdk-8 AS build
WORKDIR /app
COPY pom.xml ./
RUN mvn -B -q dependency:go-offline || true
COPY src ./src
COPY WebContent ./WebContent
COPY --from=css-purge /build/WebContent/styles.css ./WebContent/styles.css
COPY --from=css-purge /build/WebContent/pikaday.css ./WebContent/pikaday.css
RUN mvn -B -q package -DskipTests

# ---- Stage 3: minimal production runtime image ----
FROM open-liberty:full-java8-openj9
COPY --chown=1001:0 server.xml /config/server.xml
COPY --from=build --chown=1001:0 /app/target/modresorts-*.war /config/apps/modresorts.war
EXPOSE 9080
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD wget -qO- http://localhost:9080/health || exit 1
