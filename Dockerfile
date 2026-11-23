# ---------- Stage 1: strip unused CSS with PurgeCSS ----------
FROM node:18-alpine AS css-build
WORKDIR /app
COPY package.json purgecss.config.js ./
RUN npm install --no-audit --no-fund
COPY WebContent ./WebContent
RUN npm run purgecss

# ---------- Stage 2: build the WAR using purged CSS ----------
FROM maven:3.9-eclipse-temurin-8 AS app-build
WORKDIR /build
COPY pom.xml .
RUN mvn -B -q dependency:go-offline
COPY src ./src
COPY WebContent ./WebContent
# Replace original CSS with purged versions
COPY --from=css-build /app/purged-css/styles.css ./WebContent/styles.css
COPY --from=css-build /app/purged-css/pikaday.css ./WebContent/pikaday.css
RUN mvn -B -q package -DskipTests

# ---------- Stage 3: minimal runtime image ----------
FROM icr.io/appcafe/open-liberty:full-java8-openj9-ubi
COPY --chown=1001:0 server.xml /config/server.xml
COPY --from=app-build --chown=1001:0 /build/target/modresorts-2.0.0.war /config/apps/modresorts.war
EXPOSE 9080
