# ---------- Build stage ----------
FROM maven:3.9.4-eclipse-temurin-8 AS builder
WORKDIR /workspace

# Cache dependencies first
COPY pom.xml .
RUN mvn -B dependency:go-offline || true

# Copy sources and build the WAR
COPY src ./src
COPY WebContent ./WebContent
RUN mvn -B clean package -DskipTests

# ---------- Servlet container source (Tomcat 9 = javax.servlet namespace) ----------
FROM tomcat:9.0-jdk8-temurin AS tomcat

# ---------- Runtime stage ----------
FROM eclipse-temurin:8-jdk

ENV TZ=UTC \
    LANG=C.UTF-8 \
    CATALINA_HOME=/opt/tomcat \
    CATALINA_BASE=/opt/tomcat \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Dfile.encoding=UTF-8 -Duser.timezone=UTC -Djava.security.egd=file:/dev/./urandom"

COPY --from=tomcat /usr/local/tomcat /opt/tomcat

RUN rm -rf /opt/tomcat/webapps/* \
    && groupadd --system --gid 1001 appgroup \
    && useradd --system --uid 1001 --gid appgroup --home-dir /opt/tomcat --shell /usr/sbin/nologin appuser

COPY --from=builder /workspace/target/*.war /opt/tomcat/webapps/ROOT.war

RUN chown -R appuser:appgroup /opt/tomcat

USER appuser
WORKDIR /opt/tomcat

EXPOSE 8080

# catalina.sh run keeps Tomcat in the foreground and forwards SIGTERM for graceful shutdown
ENTRYPOINT ["/opt/tomcat/bin/catalina.sh", "run"]
