# ---- Stage 1: strip unused CSS with PurgeCSS ----
FROM node:20-alpine AS css-purge
WORKDIR /build
RUN npm install --global purgecss@5
COPY WebContent ./WebContent
COPY purgecss.config.js ./purgecss.config.js
RUN purgecss --config ./purgecss.config.js \
    && cp purged-css/styles.css WebContent/styles.css

# ---- Stage 2: build the WAR using purged CSS ----
FROM maven:3.9-eclipse-temurin-8 AS build
WORKDIR /app
COPY pom.xml .
COPY src ./src
COPY WebContent ./WebContent
COPY --from=css-purge /build/WebContent/styles.css ./WebContent/styles.css
RUN mvn -B -q package -DskipTests

# ---- Stage 3: minimal runtime image ----
FROM icr.io/appcafe/open-liberty:kernel-slim-java8-openj9-ubi
COPY --chown=1001:0 --from=build /app/target/modresorts-2.0.0.war /config/apps/modresorts.war
RUN printf '<server>\n  <featureManager>\n    <feature>javaee-7.0</feature>\n  </featureManager>\n  <httpEndpoint id="defaultHttpEndpoint" host="*" httpPort="9080" httpsPort="9443"/>\n  <webApplication location="modresorts.war" contextRoot="/"/>\n</server>\n' > /config/server.xml \
    && features.sh
EXPOSE 9080
