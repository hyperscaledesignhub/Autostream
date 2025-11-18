FROM eclipse-temurin:17-jre

WORKDIR /app

# Install bash, curl, and getent for hostname resolution and Kubernetes API access
RUN apt-get update && apt-get install -y bash curl netbase && rm -rf /var/lib/apt/lists/*

# Copy the demo JAR
COPY target/fluss-flink-realtime-demo.jar /app/fluss-flink-realtime-demo.jar

# Copy entrypoint script
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Use entrypoint script
ENTRYPOINT ["/app/entrypoint.sh"]

