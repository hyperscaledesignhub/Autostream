#
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

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

# Export variables for envsubst
export NAMESPACE
export DEMO_IMAGE_REPO
export DEMO_IMAGE_TAG

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
        --set persistence.enabled=true \
        --set persistence.storageClass=local-storage \
        --set persistence.size=500Gi \
        --set configurationOverrides."zookeeper\.address"="zk-svc.${NAMESPACE}.svc.cluster.local:2181" \
        --wait=false
else
    helm upgrade --install fluss "${SCRIPT_DIR}/../helm-charts/fluss" \
        --namespace ${NAMESPACE} \
        --set persistence.enabled=true \
        --set persistence.storageClass=local-storage \
        --set persistence.size=500Gi \
        --set configurationOverrides."zookeeper\.address"="zk-svc.${NAMESPACE}.svc.cluster.local:2181" \
        --wait=false
fi

# 4. Deploy Flink cluster
echo "[4/8] Deploying Flink cluster..."
# Flink image is hardcoded to apache/flink:1.20.3-scala_2.12-java17
# Use envsubst for namespace and DEMO_IMAGE_REPO/DEMO_IMAGE_TAG (for init container)
# Create Flink service account first
envsubst < "${K8S_DIR}/flink/flink-serviceaccount.yaml" | kubectl apply -f -
# Apply ConfigMap with namespace substitution
envsubst < "${K8S_DIR}/flink/flink-config.yaml" | kubectl apply -f -
# Apply JobManager and TaskManager (namespace and DEMO_IMAGE_REPO/DEMO_IMAGE_TAG for init container)
envsubst < "${K8S_DIR}/flink/flink-jobmanager.yaml" | kubectl apply -f -
envsubst < "${K8S_DIR}/flink/flink-taskmanager.yaml" | kubectl apply -f -

# 4.1. Update Flink ConfigMap with S3 checkpoint configuration
echo "[4.1/9] Updating Flink ConfigMap with S3 checkpoint configuration..."
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"
CLUSTER_NAME="fluss-eks-cluster"

if command -v terraform &> /dev/null && [ -d "${TERRAFORM_DIR}" ]; then
    cd "${TERRAFORM_DIR}"
    S3_BUCKET=$(terraform output -raw flink_s3_bucket_name 2>/dev/null || echo "")
    cd - > /dev/null
    
    if [ -n "$S3_BUCKET" ]; then
        echo "  S3 Bucket: $S3_BUCKET"
        
        # Get current ConfigMap
        CURRENT_CONFIG=$(kubectl get configmap flink-config -n "${NAMESPACE}" -o jsonpath='{.data.flink-conf\.yaml}' 2>/dev/null || echo "")
        
        if [ -n "$CURRENT_CONFIG" ]; then
            # Replace placeholder with actual bucket name (using s3:// as in reference)
            UPDATED_CONFIG=$(echo "$CURRENT_CONFIG" | \
                sed "s|s3://fluss-eks-cluster-flink-state-PLACEHOLDER/flink-checkpoints/fluss-eks-cluster/|s3://${S3_BUCKET}/flink-checkpoints/${CLUSTER_NAME}/|g" | \
                sed "s|s3://fluss-eks-cluster-flink-state-PLACEHOLDER/flink-savepoints/fluss-eks-cluster/|s3://${S3_BUCKET}/flink-savepoints/${CLUSTER_NAME}/|g" | \
                sed "s|s3a://fluss-eks-cluster-flink-state-PLACEHOLDER/flink-checkpoints/fluss-eks-cluster/|s3://${S3_BUCKET}/flink-checkpoints/${CLUSTER_NAME}/|g" | \
                sed "s|s3a://fluss-eks-cluster-flink-state-PLACEHOLDER/flink-savepoints/fluss-eks-cluster/|s3://${S3_BUCKET}/flink-savepoints/${CLUSTER_NAME}/|g")
            
            # Update ConfigMap
            if command -v jq &> /dev/null; then
                kubectl patch configmap flink-config -n "${NAMESPACE}" \
                    --type merge \
                    -p "{\"data\":{\"flink-conf.yaml\":$(echo "$UPDATED_CONFIG" | jq -Rs .)}}" 2>/dev/null && \
                echo "  ✓ ConfigMap updated with S3 checkpoint paths"
            else
                echo "  ⚠ jq not found, skipping S3 ConfigMap update (will use placeholder)"
            fi
        else
            echo "  ⚠ ConfigMap not found yet, will be updated when Flink pods are ready"
        fi
    else
        echo "  ⚠ S3 bucket not found in Terraform outputs, skipping S3 configuration"
    fi
else
    echo "  ⚠ Terraform not found or directory missing, skipping S3 configuration update"
fi

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

# 6. Deploy ServiceMonitors and PodMonitors for Prometheus
echo "[6/8] Deploying ServiceMonitors and PodMonitors for Prometheus..."
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

# 7. Deploy Grafana dashboard (if exists)
echo "[7/8] Deploying Grafana dashboard..."
if [ -f "${K8S_DIR}/monitoring/grafana-dashboard.yaml" ]; then
    kubectl apply -f "${K8S_DIR}/monitoring/grafana-dashboard.yaml"
    echo "  ✓ Grafana dashboard ConfigMap deployed"
    
    # Import dashboard via Grafana API to ensure it's visible
    echo "  Importing dashboard via Grafana API..."
    GRAFANA_USER="${GRAFANA_USER:-admin}"
    GRAFANA_PASS="${GRAFANA_PASS:-admin123}"
    GRAFANA_POD=$(kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -n "${GRAFANA_POD}" ]; then
        # Wait a moment for Grafana to be ready
        sleep 5
        
        # Extract dashboard JSON from ConfigMap
        DASHBOARD_JSON_CONTENT=$(kubectl get configmap -n monitoring fluss-flink-dashboard -o jsonpath='{.data.fluss-flink-dashboard\.json}' 2>/dev/null || echo "")
        
        if [ -n "${DASHBOARD_JSON_CONTENT}" ]; then
            # Prepare dashboard payload (ensure overwrite is set)
            if command -v jq &> /dev/null; then
                DASHBOARD_PAYLOAD=$(echo "${DASHBOARD_JSON_CONTENT}" | jq '. + {overwrite: true}' 2>/dev/null || echo "${DASHBOARD_JSON_CONTENT}")
            else
                DASHBOARD_PAYLOAD="${DASHBOARD_JSON_CONTENT}"
            fi
            
            # Import via Grafana API
            IMPORT_RESPONSE=$(kubectl exec -n monitoring "${GRAFANA_POD}" -c grafana -- curl -s -X POST \
                "http://localhost:3000/api/dashboards/db" \
                -H "Content-Type: application/json" \
                -u "${GRAFANA_USER}:${GRAFANA_PASS}" \
                -d "${DASHBOARD_PAYLOAD}" 2>/dev/null || echo "")
            
            if echo "${IMPORT_RESPONSE}" | grep -q '"status":"success"'; then
                echo "  ✓ Dashboard imported successfully via Grafana API!"
            else
                echo "  ⚠ Dashboard import via API failed (may need manual import)"
                echo "  Dashboard ConfigMap is deployed, Grafana should auto-discover it"
            fi
        else
            echo "  ⚠ Could not extract dashboard JSON from ConfigMap"
        fi
    else
        echo "  ⚠ Grafana pod not found, skipping API import"
        echo "  Dashboard ConfigMap is deployed, Grafana should auto-discover it"
    fi
else
    echo "  No Grafana dashboard YAML found, skipping..."
fi

# 8. Wait for components to be ready
echo "[8/8] Waiting for components to be ready..."
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

