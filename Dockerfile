# ---- Stage 1: strip unused CSS with PurgeCSS ----
FROM node:18-alpine AS css-purge
WORKDIR /build
COPY package.json ./
RUN npm install --no-audit --no-fund
COPY purgecss.config.js ./
COPY WebContent ./WebContent
RUN npx purgecss --config ./purgecss.config.js

# ---- Stage 2: build the WAR using the purged stylesheet ----
FROM maven:3.8-eclipse-temurin-8 AS build
WORKDIR /app
COPY pom.xml ./
COPY src ./src
COPY WebContent ./WebContent
COPY --from=css-purge /build/purged-css/styles.css ./WebContent/styles.css
RUN mvn -B -DskipTests package

# ---- Stage 3: minimal runtime image ----
FROM tomcat:9.0-jre8-temurin
RUN rm -rf /usr/local/tomcat/webapps/*
COPY --from=build /app/target/modresorts-2.0.0.war /usr/local/tomcat/webapps/ROOT.war
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --retries=3 CMD curl -fs http://localhost:8080/health || exit 1
CMD ["catalina.sh", "run"]
