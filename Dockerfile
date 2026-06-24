# Multi-stage build: compile with Maven, produce small runtime image.
# BuildKit-friendly (use --progress=plain and cache mounts in CI)
ARG INCLUDE_GUI=false
FROM maven:3.9.6-eclipse-temurin-21 AS build
WORKDIR /workspace

# Copy only the files needed to resolve dependencies first (good cache hit)
COPY pom.xml ./
# If multi-module, copy each module pom before sources to maximize cache
# COPY module-a/pom.xml module-a/pom.xml
# COPY module-b/pom.xml module-b/pom.xml

# Pre-fetch dependencies (requires BuildKit to use mount cache)
RUN --mount=type=cache,target=/root/.m2 mvn -B -T 1C dependency:go-offline

# Copy the rest of the source and build
COPY src ./src
# Copy other resources if present (e.g., resources, modules)
# COPY module-a/src module-a/src
RUN --mount=type=cache,target=/root/.m2 mvn -B -T 1C -DskipTests package

# Runtime stage: slim base, GUI libs only optionally added via build-arg
FROM eclipse-temurin:21-jre-jammy AS runtime
LABEL maintainer="platform-team"

ARG INCLUDE_GUI=false
# Install only minimal packages; GUI libs installed only when needed
RUN if [ "${INCLUDE_GUI}" = "true" ]; then \
      apt-get update && apt-get install -y --no-install-recommends \
        xvfb libgtk-3-0 libxrender1 libxtst6 fontconfig ca-certificates \
      && rm -rf /var/lib/apt/lists/* ; \
    else \
      apt-get update && apt-get install -y --no-install-recommends ca-certificates \
      && rm -rf /var/lib/apt/lists/* ; \
    fi

# Use numeric uid/gid for consistent non-root behavior
RUN groupadd --system app && useradd --system --gid app --create-home --home-dir /home/app --shell /usr/sbin/nologin app

WORKDIR /app
# Copy built artifact(s). Prefer exact artifact name if known for determinism.
COPY --from=build /workspace/target/*.jar ./app.jar
RUN chown -R app:app /app

USER app
EXPOSE 8080

ENV JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0"
ENV INCLUDE_GUI=${INCLUDE_GUI}

# If GUI enabled, start Xvfb; otherwise run normally. Keeps runtime lean by default.
ENTRYPOINT ["sh", "-c", "if [ \"${INCLUDE_GUI}\" = \"true\" ]; then Xvfb :99 -screen 0 1920x1080x24 > /tmp/xvfb.log 2>&1 & export DISPLAY=:99; fi; exec java ${JAVA_OPTS} -jar /app/app.jar"]