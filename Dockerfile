# ---- Stage 1: strip unused CSS with PurgeCSS ----
FROM node:20-alpine AS css-purge
WORKDIR /build
RUN npm install -g purgecss@6
COPY purgecss.config.js ./
COPY WebContent ./WebContent
RUN purgecss --config purgecss.config.js

# ---- Stage 2: build the application ----
FROM maven:3.9-eclipse-temurin-8 AS build
WORKDIR /build
COPY pom.xml ./
COPY src ./src
COPY WebContent ./WebContent
# Overwrite CSS with the purged versions
COPY --from=css-purge /build/purged-css/styles.css ./WebContent/styles.css
COPY --from=css-purge /build/purged-css/pikaday.css ./WebContent/pikaday.css
RUN mvn -B -DskipTests package

# ---- Stage 3: minimal runtime image ----
FROM eclipse-temurin:8-jre
WORKDIR /app
COPY --from=build /build/target/modresorts-2.0.0.war app.war
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.war"]
