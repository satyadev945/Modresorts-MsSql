# Stage 1: build the WAR (exploded webapp is produced under target/)
FROM maven:3.9-eclipse-temurin-8 AS build
WORKDIR /build
COPY pom.xml .
COPY src ./src
COPY WebContent ./WebContent
RUN mvn -B -q package -DskipTests

# Stage 2: strip unused CSS with PurgeCSS (cz-css-1005)
FROM node:20-alpine AS purgecss
WORKDIR /assets
RUN npm install -g purgecss@6
COPY WebContent/styles.css ./styles.css
COPY WebContent/index.html WebContent/login.jsp WebContent/main.js ./content/
RUN purgecss --css styles.css \
      --content "content/*.html" "content/*.jsp" "content/*.js" \
      --output purged/

# Stage 3: minimal runtime image
FROM tomcat:9.0-jdk8-temurin
RUN rm -rf /usr/local/tomcat/webapps/*
COPY --from=build /build/target/modresorts-2.0.0 /usr/local/tomcat/webapps/ROOT
# Overlay purged stylesheet
COPY --from=purgecss /assets/purged/styles.css /usr/local/tomcat/webapps/ROOT/styles.css
EXPOSE 8080
CMD ["catalina.sh", "run"]
