# Build stage: compile with Maven (uses cache mounts for speed)
FROM maven:3.9.6-eclipse-temurin-21 AS build
WORKDIR /workspace

# Copy only dependency descriptors first for cache efficiency
COPY pom.xml mvnw ./
COPY .mvn .mvn
RUN --mount=type=cache,target=/root/.m2 mvn -B -T 1C -DskipTests dependency:go-offline

# Copy source and build artifact
COPY src ./src
RUN --mount=type=cache,target=/root/.m2 mvn -B -T 1C -DskipTests package

# Runtime stage: small, stable base with required GUI libs and Xvfb
FROM eclipse-temurin:21-jre-jammy
LABEL maintainer="platform-team"

# Install only minimal packages needed for headless/AWT support and certificate trust
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

# Copy artifact produced in build stage; adjust pattern if artifact name differs
COPY --from=build /workspace/target/*.jar ./app.jar
RUN chown -R app:app /app

# Switch to non-root user
USER app

EXPOSE 8080

# Reasonable defaults; callers can override JAVA_OPTS
ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"

# Start Xvfb on display :99 then launch the JVM (keeps container self-contained for GUI tests)
ENTRYPOINT ["sh", "-c", "Xvfb :99 -screen 0 1920x1080x24 > /tmp/xvfb.log 2>&1 & export DISPLAY=:99 && exec java $JAVA_OPTS -jar /app/app.jar"]