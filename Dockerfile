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
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace
COPY pom.xml ./
RUN mvn -B -q dependency:resolve || true
COPY src ./src
COPY WebContent ./WebContent
COPY --from=css-purge /build/WebContent/styles.css ./WebContent/styles.css
COPY --from=css-purge /build/WebContent/pikaday.css ./WebContent/pikaday.css
RUN mvn -B clean package -DskipTests

# ---- Stage 3: fetch and prepare the Apache Tomcat servlet container ----
# The application is a Java EE 7 WAR (servlets/filters, no embedded server),
# so a servlet container is required on top of the JRE runtime image.
FROM maven:3.9.4-eclipse-temurin-8 AS tomcat
ARG TOMCAT_VERSION=9.0.89
RUN set -eux; \
    curl -fsSL -o /tmp/tomcat.tar.gz "https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz"; \
    curl -fsSL -o /tmp/tomcat.tar.gz.sha512 "https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz.sha512"; \
    echo "$(cut -d' ' -f1 /tmp/tomcat.tar.gz.sha512)  /tmp/tomcat.tar.gz" | sha512sum -c -; \
    mkdir -p /opt/tomcat; \
    tar -xzf /tmp/tomcat.tar.gz -C /opt/tomcat --strip-components=1; \
    rm -rf /opt/tomcat/webapps/* /opt/tomcat/bin/*.bat; \
    sed -i 's/port="8005"/port="-1"/' /opt/tomcat/conf/server.xml

# ---- Stage 4: minimal production runtime image ----
FROM eclipse-temurin:8-jre

ENV CATALINA_HOME=/opt/tomcat \
    TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Dfile.encoding=UTF-8 -Duser.timezone=UTC -Djava.security.egd=file:/dev/./urandom"

RUN groupadd -r -g 1001 appgroup && useradd -r -u 1001 -g appgroup -d /opt/tomcat -s /sbin/nologin appuser

COPY --from=tomcat --chown=1001:1001 /opt/tomcat /opt/tomcat
COPY --from=builder --chown=1001:1001 /workspace/target/modresorts-*.war /opt/tomcat/webapps/ROOT.war

WORKDIR /opt/tomcat
USER 1001:1001

EXPOSE 8080

# catalina.sh run execs the JVM in the foreground so SIGTERM triggers graceful shutdown
CMD ["/opt/tomcat/bin/catalina.sh", "run"]
