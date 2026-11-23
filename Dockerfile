# Stage 1: build the WAR (exploded webapp is produced under target/)
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace
# Cache dependencies: copy the POM first
COPY pom.xml .
RUN mvn -B dependency:go-offline
COPY src ./src
COPY WebContent ./WebContent
RUN mvn -B clean package -DskipTests

# Stage 2: strip unused CSS with PurgeCSS
FROM node:20-alpine AS purgecss
WORKDIR /assets
RUN npm install -g purgecss@6
COPY WebContent/styles.css ./styles.css
COPY WebContent/index.html WebContent/login.jsp WebContent/main.js ./content/
RUN purgecss --css styles.css \
      --content "content/*.html" "content/*.jsp" "content/*.js" \
      --output purged/

# Stage 3: Tomcat distribution (servlet container for the WAR; javax.* servlet API)
FROM tomcat:9.0-jdk8-temurin AS tomcat-dist

# Stage 4: runtime image based on the requested base image
FROM eclipse-temurin:8-jdk
ENV CATALINA_HOME=/usr/local/tomcat \
    TZ=UTC \
    LANG=C.UTF-8 \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:InitialRAMPercentage=25.0 -Dfile.encoding=UTF-8 -Duser.timezone=UTC -Djava.security.egd=file:/dev/./urandom"
ENV PATH=$CATALINA_HOME/bin:$PATH
WORKDIR /usr/local/tomcat
COPY --from=tomcat-dist /usr/local/tomcat /usr/local/tomcat
RUN rm -rf /usr/local/tomcat/webapps/* \
    && groupadd -r appgroup \
    && useradd -r -g appgroup -d /usr/local/tomcat -s /sbin/nologin appuser
COPY --from=builder /workspace/target/modresorts-2.0.0 /usr/local/tomcat/webapps/ROOT
# Overlay purged stylesheet
COPY --from=purgecss /assets/purged/styles.css /usr/local/tomcat/webapps/ROOT/styles.css
RUN chown -R appuser:appgroup /usr/local/tomcat
USER appuser
EXPOSE 8080
# catalina.sh run keeps Tomcat in the foreground and forwards SIGTERM for graceful shutdown
CMD ["catalina.sh", "run"]
