# ---- Stage 1: strip unused CSS with PurgeCSS ----
FROM node:18-alpine AS css-purge
WORKDIR /build
COPY package.json ./
RUN npm install --no-audit --no-fund
COPY purgecss.config.js ./
COPY WebContent ./WebContent
RUN npx purgecss --config ./purgecss.config.js

# ---- Stage 2: build the WAR using the purged stylesheet ----
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace
# Cache dependencies: copy pom.xml first
COPY pom.xml ./
RUN mvn -B dependency:go-offline || true
COPY src ./src
COPY WebContent ./WebContent
COPY --from=css-purge /build/purged-css/styles.css ./WebContent/styles.css
RUN mvn -B clean package -DskipTests

# ---- Stage 3: servlet container source (Tomcat 9 / javax.servlet, Java 8) ----
FROM tomcat:9.0-jre8-temurin AS tomcat

# ---- Stage 4: runtime on the explicit base image (eclipse-temurin:8-jre) ----
FROM eclipse-temurin:8-jre

ENV TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    CATALINA_HOME=/usr/local/tomcat \
    CATALINA_BASE=/usr/local/tomcat \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Xms256m -Dfile.encoding=UTF-8 -Duser.timezone=UTC -Djava.security.egd=file:/dev/./urandom" \
    WEATHER_API_KEY=""
ENV PATH="${CATALINA_HOME}/bin:${PATH}"

# Non-root user (home dir is used by the app, user.home, for reservations export)
RUN groupadd -r -g 1001 app && useradd -r -u 1001 -g app -m -d /home/app -s /sbin/nologin app

# Tomcat distribution from the official tomcat image (no package manager needed)
COPY --from=tomcat --chown=app:app /usr/local/tomcat /usr/local/tomcat
RUN rm -rf /usr/local/tomcat/webapps/* && mkdir -p /usr/local/tomcat/webapps && chown app:app /usr/local/tomcat/webapps

COPY --from=builder --chown=app:app /workspace/target/modresorts-2.0.0.war /usr/local/tomcat/webapps/ROOT.war

WORKDIR /usr/local/tomcat
USER app

EXPOSE 8080

# exec form so Tomcat receives SIGTERM for graceful shutdown
CMD ["catalina.sh", "run"]
