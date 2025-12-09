# Dockerfile for Fluss Flink Demo Job
# Builds the JAR and includes it in Flink image for local:// submission

# Stage 1: Build the JAR using Maven
FROM --platform=linux/amd64 maven:3.9-eclipse-temurin-17 AS builder

WORKDIR /build

# Copy POM files
COPY ../../../demos/demo/fluss_flink_realtime_demo/pom.xml .
COPY ../../../demos/demo/fluss_flink_realtime_demo/fluss_flink_realtime_demo/pom.xml fluss_flink_realtime_demo/ 2>/dev/null || true

# Download dependencies (cached layer)
RUN mvn -B dependency:go-offline -f pom.xml || true

# Copy source code
COPY ../../../demos/demo/fluss_flink_realtime_demo/src fluss_flink_realtime_demo/src 2>/dev/null || \
     COPY ../../../demos/demo/fluss_flink_realtime_demo/src src

# Build the JAR with all dependencies
RUN mvn clean package -DskipTests -f pom.xml || \
    (cd ../../../demos/demo/fluss_flink_realtime_demo && mvn clean package -DskipTests)

# Find the built JAR
RUN find . -name "*.jar" -not -name "*-sources.jar" -not -name "*-javadoc.jar" | head -1 > /tmp/jar_path.txt

# Stage 2: Create runtime image with Flink
FROM --platform=linux/amd64 apache/flink:1.20.3-scala_2.12-java17

# Ensure Prometheus metrics reporter is in plugins directory (required for Flink 1.20.3)
# The base image should already have it, but we'll verify and ensure it's properly configured
RUN mkdir -p /opt/flink/plugins/metrics-prometheus && \
    if [ ! -f /opt/flink/plugins/metrics-prometheus/flink-metrics-prometheus-1.20.3.jar ]; then \
        curl -L https://repo1.maven.org/maven2/org/apache/flink/flink-metrics-prometheus/1.20.3/flink-metrics-prometheus-1.20.3.jar \
            -o /opt/flink/plugins/metrics-prometheus/flink-metrics-prometheus-1.20.3.jar && \
        chmod 644 /opt/flink/plugins/metrics-prometheus/flink-metrics-prometheus-1.20.3.jar; \
    fi

# Set working directory
WORKDIR /opt/flink/usrlib

# Copy the built JAR from builder stage
# Try to find JAR in standard locations
COPY --from=builder /build/target/fluss-flink-realtime-demo.jar /opt/flink/usrlib/fluss-flink-realtime-demo.jar 2>/dev/null || \
COPY --from=builder /build/fluss_flink_realtime_demo/target/fluss-flink-realtime-demo.jar /opt/flink/usrlib/fluss-flink-realtime-demo.jar 2>/dev/null || \
COPY --from=builder /build/$(cat /tmp/jar_path.txt 2>/dev/null || echo "target/fluss-flink-realtime-demo.jar") /opt/flink/usrlib/fluss-flink-realtime-demo.jar

# Verify the JAR is present
RUN ls -lh /opt/flink/usrlib/fluss-flink-realtime-demo.jar || \
    (echo "ERROR: JAR file not found" && exit 1)

# Metadata
LABEL maintainer="Fluss Team"
LABEL description="Fluss Flink Realtime Demo - JAR embedded for local:// submission"
LABEL version="0.1.0"
LABEL flink.version="1.20.3"

# The Flink cluster will use this image, and jobs can reference the JAR via local://
# No ENTRYPOINT needed - Flink deployments handle the lifecycle

