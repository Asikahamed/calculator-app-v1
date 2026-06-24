# Multi-stage build for a Java/Maven application (Java 21)
# Use the Maven tool in the base image (do not rely on mvnw/.mvn being present)

FROM maven:3.9.6-eclipse-temurin-21 AS build
WORKDIR /workspace

# Copy only pom.xml first to leverage Docker layer cache for dependencies
COPY pom.xml ./

# Pre-fetch dependencies (uses buildkit cache mount)
RUN --mount=type=cache,target=/root/.m2 mvn -B -T 1C dependency:go-offline

# Copy source and build artifact
COPY src ./src
# If your project has additional modules/resources, copy them as needed:
# COPY module-a/pom.xml module-a/pom.xml
# COPY module-a/src module-a/src
RUN --mount=type=cache,target=/root/.m2 mvn -B -T 1C -DskipTests package

# Runtime stage: small, stable base with required GUI libs and Xvfb
FROM eclipse-temurin:21-jre-jammy
LABEL maintainer="platform-team"

# Install only minimal packages needed for AWT/Swing tests and certs
RUN apt-get update && apt-get install -y --no-install-recommends \
      xvfb \
      libgtk-3-0 \
      libxrender1 \
      libxtst6 \
      fontconfig \
      ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd --system app && useradd --system --gid app --create-home --home-dir /home/app --shell /usr/sbin/nologin app

WORKDIR /app

# Copy built artifact(s). Adjust pattern if your module produces a different JAR name.
COPY --from=build /workspace/target/*.jar ./app.jar
RUN chown -R app:app /app

USER app
EXPOSE 8080

ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"

# Start Xvfb and run the app (keeps container self-contained for GUI tests)
ENTRYPOINT ["sh", "-c", "Xvfb :99 -screen 0 1920x1080x24 > /tmp/xvfb.log 2>&1 & export DISPLAY=:99 && exec java $JAVA_OPTS -jar /app/app.jar"]