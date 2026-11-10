# ---------- Servlet container source (Tomcat 9 / javax.servlet, Java 8) ----------
FROM tomcat:9.0-jdk8-temurin AS tomcat

# ---------- Build stage ----------
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace

# Cache dependencies: copy the POM first
COPY pom.xml .
RUN mvn -B dependency:resolve

# Copy sources and build the WAR
COPY src ./src
COPY WebContent ./WebContent
RUN mvn -B clean package -DskipTests

# ---------- Runtime stage ----------
FROM eclipse-temurin:8-jdk

ENV CATALINA_HOME=/opt/tomcat \
    TZ=UTC \
    LANG=C.UTF-8 \
    JAVA_OPTS="-Xms256m -Xmx512m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Dfile.encoding=UTF-8 -Djava.security.egd=file:/dev/./urandom"

# Tomcat from the official image (no package manager usage in runtime stage)
COPY --from=tomcat /usr/local/tomcat ${CATALINA_HOME}

# Non-root user
RUN groupadd -r modres && useradd -r -m -g modres modres \
    && rm -rf ${CATALINA_HOME}/webapps/* \
    && mkdir -p ${CATALINA_HOME}/logs ${CATALINA_HOME}/temp ${CATALINA_HOME}/work \
    && chown -R modres:modres ${CATALINA_HOME}

# Deploy as root context
COPY --from=builder --chown=modres:modres /workspace/target/*.war ${CATALINA_HOME}/webapps/ROOT.war

USER modres
WORKDIR ${CATALINA_HOME}

EXPOSE 8080

# catalina.sh run keeps Tomcat in the foreground and handles SIGTERM for graceful shutdown
ENTRYPOINT ["/opt/tomcat/bin/catalina.sh", "run"]
