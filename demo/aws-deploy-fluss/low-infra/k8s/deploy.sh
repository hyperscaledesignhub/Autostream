#!/bin/bash
set -euo pipefail

# Deployment script for Kubernetes resources
# Usage: ./deploy.sh [namespace] [demo-image-repo] [demo-image-tag] [fluss-image-repo]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="${SCRIPT_DIR}"

NAMESPACE="${1:-fluss}"
DEMO_IMAGE_REPO="${2:-}"
DEMO_IMAGE_TAG="${3:-latest}"
FLUSS_IMAGE_REPO="${4:-apache/fluss:0.8.0-incubating}"

echo "=== Deploying Kubernetes Resources ==="
echo "Namespace: ${NAMESPACE}"
echo "Demo Image: ${DEMO_IMAGE_REPO}:${DEMO_IMAGE_TAG}"
echo "Fluss Image: ${FLUSS_IMAGE_REPO}"
echo ""

# Check kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl is not installed or not in PATH"
    exit 1
fi

# Check helm is available (for Fluss and monitoring)
if ! command -v helm &> /dev/null; then
    echo "ERROR: helm is not installed or not in PATH"
    exit 1
fi

# 1. Create namespace
echo "[1/8] Creating namespace..."
kubectl apply -f "${K8S_DIR}/namespace/namespace.yaml"

# 2. Deploy ZooKeeper
echo "[2/8] Deploying ZooKeeper..."
kubectl apply -f "${K8S_DIR}/zookeeper/zookeeper.yaml"

# Wait for ZooKeeper to be ready
echo "Waiting for ZooKeeper to be ready..."
kubectl wait --for=condition=ready pod -l app=zookeeper -n ${NAMESPACE} --timeout=120s || true

# 3. Deploy Fluss via Helm
echo "[3/8] Deploying Fluss via Helm..."
if [ -n "${FLUSS_IMAGE_REPO}" ]; then
    # Extract registry, repository, and tag from image
    if [[ "${FLUSS_IMAGE_REPO}" == *".dkr.ecr."* ]]; then
        # ECR format: <account>.dkr.ecr.<region>.amazonaws.com/<repo> or <account>.dkr.ecr.<region>.amazonaws.com/<repo>:<tag>
        if [[ "${FLUSS_IMAGE_REPO}" == *":"* ]]; then
            # Has tag
            FLUSS_REPO_WITHOUT_TAG="${FLUSS_IMAGE_REPO%%:*}"
            FLUSS_TAG="${FLUSS_IMAGE_REPO##*:}"
        else
            # No tag, use default
            FLUSS_REPO_WITHOUT_TAG="${FLUSS_IMAGE_REPO}"
            FLUSS_TAG="0.8.0-incubating"
        fi
        # For ECR, registry is empty and repository is the full ECR URL without tag
        FLUSS_REGISTRY=""
        FLUSS_REPO="${FLUSS_REPO_WITHOUT_TAG}"
    else
        # Docker Hub format: <repo>:<tag> or <registry>/<repo>:<tag>
        if [[ "${FLUSS_IMAGE_REPO}" == *":"* ]]; then
            FLUSS_REPO="${FLUSS_IMAGE_REPO%%:*}"
            FLUSS_TAG="${FLUSS_IMAGE_REPO##*:}"
        else
            FLUSS_REPO="${FLUSS_IMAGE_REPO}"
            FLUSS_TAG="0.8.0-incubating"
        fi
        FLUSS_REGISTRY="docker.io"
    fi
    
    helm upgrade --install fluss "${SCRIPT_DIR}/../helm-charts/fluss" \
        --namespace ${NAMESPACE} \
        --set image.registry="${FLUSS_REGISTRY}" \
        --set image.repository="${FLUSS_REPO}" \
        --set image.tag="${FLUSS_TAG}" \
        --set configurationOverrides."zookeeper\.address"="zk-svc.${NAMESPACE}.svc.cluster.local:2181" \
        --wait=false
else
    helm upgrade --install fluss "${SCRIPT_DIR}/../helm-charts/fluss" \
        --namespace ${NAMESPACE} \
        --set configurationOverrides."zookeeper\.address"="zk-svc.${NAMESPACE}.svc.cluster.local:2181" \
        --wait=false
fi

# 4. Deploy Flink cluster
echo "[4/8] Deploying Flink cluster..."
kubectl apply -f "${K8S_DIR}/flink/flink-config.yaml"
kubectl apply -f "${K8S_DIR}/flink/flink-jobmanager.yaml"
kubectl apply -f "${K8S_DIR}/flink/flink-taskmanager.yaml"

# 5. Deploy monitoring (Prometheus/Grafana)
echo "[5/8] Deploying monitoring stack..."
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
    --version 55.5.0 \
    --namespace monitoring \
    --set prometheus.prometheusSpec.retention=30d \
    --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
    --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
    --set grafana.enabled=true \
    --set grafana.adminUser=admin \
    --set grafana.adminPassword=admin123 \
    --set grafana.service.type=LoadBalancer \
    --set alertmanager.enabled=false \
    --wait=false

# 6. Deploy producer job (with image substitution)
echo "[6/8] Deploying producer job..."
if [ -z "${DEMO_IMAGE_REPO}" ]; then
    echo "WARNING: DEMO_IMAGE_REPO not set, skipping producer job deployment"
else
    envsubst < "${K8S_DIR}/jobs/producer-job.yaml" | kubectl apply -f -
fi

# 7. Deploy ServiceMonitors and PodMonitors for Prometheus
echo "[7/9] Deploying ServiceMonitors and PodMonitors for Prometheus..."
if [ -f "${K8S_DIR}/monitoring/servicemonitors.yaml" ]; then
    kubectl apply -f "${K8S_DIR}/monitoring/servicemonitors.yaml"
    echo "  ✓ ServiceMonitors deployed"
else
    echo "  WARNING: servicemonitors.yaml not found, skipping..."
fi
if [ -f "${K8S_DIR}/monitoring/podmonitors.yaml" ]; then
    kubectl apply -f "${K8S_DIR}/monitoring/podmonitors.yaml"
    echo "  ✓ PodMonitors deployed"
else
    echo "  WARNING: podmonitors.yaml not found, skipping..."
fi

# 8. Deploy Grafana dashboard (if exists)
echo "[8/9] Deploying Grafana dashboard..."
if [ -f "${K8S_DIR}/monitoring/grafana-dashboard.yaml" ]; then
    kubectl apply -f "${K8S_DIR}/monitoring/grafana-dashboard.yaml"
else
    echo "  No Grafana dashboard YAML found, skipping..."
fi

# 9. Wait for components to be ready
echo "[9/9] Waiting for components to be ready..."
echo "  Waiting for Flink JobManager..."
kubectl wait --for=condition=ready pod -l app=flink,component=jobmanager -n ${NAMESPACE} --timeout=300s || true
echo "  Waiting for Flink TaskManagers..."
kubectl wait --for=condition=ready pod -l app=flink,component=taskmanager -n ${NAMESPACE} --timeout=300s || true

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Check status:"
echo "  kubectl get pods -n ${NAMESPACE}"
echo "  kubectl get pods -n monitoring"
echo ""
echo "Check Flink cluster:"
echo "  kubectl get pods -n ${NAMESPACE} -l app=flink"
echo "  kubectl get nodes -l flink-component"
echo ""
echo "Check monitoring:"
echo "  kubectl get servicemonitor -n ${NAMESPACE}"
echo "  kubectl get podmonitor -n ${NAMESPACE}"
echo ""
echo "Access Flink Web UI:"
echo "  kubectl port-forward -n ${NAMESPACE} svc/flink-jobmanager 8081:8081"
echo "  Then open: http://localhost:8081"
echo ""
echo "Access Grafana:"
echo "  GRAFANA_SVC=\$(kubectl get svc -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}')"
echo "  kubectl port-forward -n monitoring svc/\$GRAFANA_SVC 3000:80"
echo "  Then open: http://localhost:3000"
echo "  Username: admin"
echo "  Password: admin123"
echo ""
echo "Access Prometheus:"
echo "  PROM_SVC=\$(kubectl get svc -n monitoring -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}')"
echo "  kubectl port-forward -n monitoring svc/\$PROM_SVC 9090:9090"
echo "  Then open: http://localhost:9090"
echo ""
echo "Submit Flink aggregator job manually:"
echo "  cd ${K8S_DIR}/flink && ./submit-job-local.sh"

