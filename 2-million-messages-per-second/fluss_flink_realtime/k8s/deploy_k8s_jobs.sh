#!/usr/bin/env bash
set -euo pipefail

# Script to build Docker image and deploy producer + Flink aggregator as Kubernetes Jobs

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# DEMO_DIR is the parent directory (where pom.xml, Dockerfile, etc. are located)
DEMO_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
WORKDIR=$(cd "${DEMO_DIR}/../../.." && pwd)
cd "${WORKDIR}"

KIND_NAME=${KIND_NAME:-fluss-kind}
IMAGE_NAME="fluss-demo"
IMAGE_TAG="latest"
FULL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"

echo "=== Building and Deploying Fluss Demo Jobs to Kind ==="

# Step 1: Build the demo JAR if needed
if [ ! -f "${DEMO_DIR}/target/fluss-flink-realtime-demo.jar" ]; then
    echo "[1/5] Building demo JAR..."
    mvn -f "${DEMO_DIR}/pom.xml" clean package
else
    echo "[1/5] Demo JAR exists, skipping build"
fi

# Step 2: Build Docker image
echo "[2/5] Building Docker image ${FULL_IMAGE}..."
cd "${DEMO_DIR}"
docker build -t "${FULL_IMAGE}" .

# Step 3: Load image into Kind
echo "[3/5] Loading ${FULL_IMAGE} into Kind cluster..."
kind load docker-image "${FULL_IMAGE}" --name "${KIND_NAME}"

# Step 4: Deploy producer Job
echo "[4/5] Deploying producer Job..."
kubectl apply -f "${SCRIPT_DIR}/k8s-producer-job.yaml"

# Step 5: Deploy Flink aggregator Job
echo "[5/5] Deploying Flink aggregator Job..."
kubectl apply -f "${SCRIPT_DIR}/k8s-flink-aggregator-job.yaml"

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Check job status:"
echo "  kubectl get jobs"
echo "  kubectl get pods -l app=fluss-producer"
echo "  kubectl get pods -l app=flink-aggregator"
echo ""
echo "View producer logs:"
echo "  kubectl logs -l app=fluss-producer --tail=50 -f"
echo ""
echo "View aggregator logs:"
echo "  kubectl logs -l app=flink-aggregator --tail=50 -f"
echo ""
echo "Delete jobs:"
echo "  kubectl delete job fluss-producer flink-aggregator"

