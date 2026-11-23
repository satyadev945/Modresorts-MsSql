# ---- Stage 1: build the WAR ----
FROM maven:3.9-eclipse-temurin-8 AS build
WORKDIR /app
COPY pom.xml .
COPY src ./src
COPY WebContent ./WebContent
RUN mvn -B -q -DskipTests package

# ---- Stage 2: purge unused CSS (PurgeCSS) ----
FROM node:20-alpine AS purgecss
WORKDIR /app
RUN npm install -g purgecss@6
COPY WebContent ./WebContent
COPY purgecss.config.js ./
RUN purgecss --config purgecss.config.js \
    && cp purged-css/styles.css WebContent/styles.css \
    && cp purged-css/pikaday.css WebContent/pikaday.css

# ---- Stage 3: production image ----
FROM tomcat:9.0-jdk8-temurin
RUN rm -rf /usr/local/tomcat/webapps/*
COPY --from=build /app/target/modresorts-2.0.0.war /tmp/app.war
RUN mkdir -p /usr/local/tomcat/webapps/ROOT \
    && cd /usr/local/tomcat/webapps/ROOT \
    && jar xf /tmp/app.war \
    && rm /tmp/app.war
# Overlay the purged (minimal) CSS
COPY --from=purgecss /app/WebContent/styles.css /usr/local/tomcat/webapps/ROOT/styles.css
COPY --from=purgecss /app/WebContent/pikaday.css /usr/local/tomcat/webapps/ROOT/pikaday.css
EXPOSE 8080
CMD ["catalina.sh", "run"]
