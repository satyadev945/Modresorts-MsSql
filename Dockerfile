# ---------- Stage 1: build the WAR with Maven ----------
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace

# Cache dependencies: copy the POM first
COPY pom.xml .
RUN mvn -B -q dependency:resolve || true

# Copy sources and web content, then build
COPY src ./src
COPY WebContent ./WebContent
RUN mvn -B clean package -DskipTests

# ---------- Stage 2: servlet container (Tomcat 9 = Servlet 4 / javax.*, Java 8 compatible) ----------
FROM tomcat:9.0-jdk8-temurin AS tomcat

# ---------- Stage 3: runtime ----------
FROM openjdk:8-jdk

ENV TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    CATALINA_HOME=/usr/local/tomcat \
    CATALINA_BASE=/usr/local/tomcat \
    CATALINA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError -Dfile.encoding=UTF-8 -Duser.timezone=UTC -Djava.security.egd=file:/dev/./urandom"

# Tomcat distribution from the tomcat stage (no package manager needed)
COPY --from=tomcat /usr/local/tomcat /usr/local/tomcat

# Non-root user
RUN groupadd --system --gid 1001 app \
    && useradd --system --uid 1001 --gid app --create-home --home-dir /home/app app \
    && rm -rf /usr/local/tomcat/webapps/* \
    && chown -R app:app /usr/local/tomcat /home/app

# Deploy the application as the ROOT context
COPY --from=builder --chown=app:app /workspace/target/*.war /usr/local/tomcat/webapps/ROOT.war

WORKDIR /usr/local/tomcat
USER app

EXPOSE 8080

# catalina.sh run keeps Tomcat in the foreground and handles SIGTERM for graceful shutdown
ENTRYPOINT ["/usr/local/tomcat/bin/catalina.sh", "run"]
