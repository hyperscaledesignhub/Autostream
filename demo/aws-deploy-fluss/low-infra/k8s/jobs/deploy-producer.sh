#!/bin/bash
set -e

# Deploy producer job to Kubernetes
# Usage: ./deploy-producer.sh [options]
# Options:
#   --namespace NAMESPACE          Kubernetes namespace (default: fluss)
#   --image IMAGE                  Docker image (default: from ECR or env)
#   --rate RATE                    Records per second (default: 2000)
#   --flush FLUSH                  Flush every N records (default: 5000)
#   --stats STATS                  Stats every N records (default: 1000)
#   --bootstrap BOOTSTRAP          Fluss coordinator address (default: coordinator-server-hs.fluss.svc.cluster.local:9124)
#   --database DATABASE            Database name (default: iot)
#   --table TABLE                  Table name (default: sensor_readings)
#   --buckets BUCKETS              Number of buckets (default: 12)
#   --wait                         Wait for job to be ready
#   --logs                         Show logs after deployment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-fluss}"
PRODUCER_RATE="${PRODUCER_RATE:-2000}"
PRODUCER_FLUSH_EVERY="${PRODUCER_FLUSH_EVERY:-5000}"
PRODUCER_STATS_EVERY="${PRODUCER_STATS_EVERY:-1000}"
BOOTSTRAP="${BOOTSTRAP:-coordinator-server-hs.fluss.svc.cluster.local:9124}"
DATABASE="${DATABASE:-iot}"
TABLE="${TABLE:-sensor_readings}"
BUCKETS="${BUCKETS:-12}"
DEMO_IMAGE_REPO="${DEMO_IMAGE_REPO:-343218179954.dkr.ecr.us-west-2.amazonaws.com/fluss-demo}"
DEMO_IMAGE_TAG="${DEMO_IMAGE_TAG:-latest}"
WAIT_FOR_READY=false
SHOW_LOGS=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --image)
            if [[ "$2" == *":"* ]]; then
                DEMO_IMAGE_REPO="${2%%:*}"
                DEMO_IMAGE_TAG="${2##*:}"
            else
                DEMO_IMAGE_REPO="$2"
            fi
            shift 2
            ;;
        --rate)
            PRODUCER_RATE="$2"
            shift 2
            ;;
        --flush)
            PRODUCER_FLUSH_EVERY="$2"
            shift 2
            ;;
        --stats)
            PRODUCER_STATS_EVERY="$2"
            shift 2
            ;;
        --bootstrap)
            BOOTSTRAP="$2"
            shift 2
            ;;
        --database)
            DATABASE="$2"
            shift 2
            ;;
        --table)
            TABLE="$2"
            shift 2
            ;;
        --buckets)
            BUCKETS="$2"
            shift 2
            ;;
        --wait)
            WAIT_FOR_READY=true
            shift
            ;;
        --logs)
            SHOW_LOGS=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --namespace NAMESPACE          Kubernetes namespace (default: fluss)"
            echo "  --image IMAGE                  Docker image (default: from ECR or env)"
            echo "  --rate RATE                    Records per second (default: 2000)"
            echo "  --flush FLUSH                  Flush every N records (default: 5000)"
            echo "  --stats STATS                  Stats every N records (default: 1000)"
            echo "  --bootstrap BOOTSTRAP          Fluss coordinator address"
            echo "  --database DATABASE            Database name (default: iot)"
            echo "  --table TABLE                  Table name (default: sensor_readings)"
            echo "  --buckets BUCKETS              Number of buckets (default: 12)"
            echo "  --wait                         Wait for job to be ready"
            echo "  --logs                         Show logs after deployment"
            echo ""
            echo "Environment variables:"
            echo "  NAMESPACE, PRODUCER_RATE, PRODUCER_FLUSH_EVERY, PRODUCER_STATS_EVERY"
            echo "  BOOTSTRAP, DATABASE, TABLE, BUCKETS"
            echo "  DEMO_IMAGE_REPO, DEMO_IMAGE_TAG"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Check kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl is not installed or not in PATH"
    exit 1
fi

# Check if namespace exists
if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
    echo "ERROR: Namespace ${NAMESPACE} does not exist"
    exit 1
fi

echo "=== Deploying Producer Job ==="
echo "Namespace: ${NAMESPACE}"
echo "Image: ${DEMO_IMAGE_REPO}:${DEMO_IMAGE_TAG}"
echo "Rate: ${PRODUCER_RATE} records/sec"
echo "Flush: every ${PRODUCER_FLUSH_EVERY} records"
echo "Stats: every ${PRODUCER_STATS_EVERY} records"
echo "Bootstrap: ${BOOTSTRAP}"
echo "Database: ${DATABASE}"
echo "Table: ${TABLE}"
echo "Buckets: ${BUCKETS}"
echo ""

# Always delete existing job before deploying
echo "[1/4] Deleting existing producer job (if any)..."
EXISTING_JOB=$(kubectl get job -n "${NAMESPACE}" fluss-producer -o name 2>/dev/null || echo "")
if [ -n "${EXISTING_JOB}" ]; then
    kubectl delete job -n "${NAMESPACE}" fluss-producer
    echo "  ✓ Existing job deleted"
    # Wait a moment for the job and pods to be fully deleted
    sleep 2
else
    echo "  ℹ No existing job found"
fi
echo ""

# Deploy producer job
echo "[2/4] Deploying producer job..."
export NAMESPACE
export DEMO_IMAGE_REPO
export DEMO_IMAGE_TAG
export PRODUCER_RATE
export PRODUCER_FLUSH_EVERY
export PRODUCER_STATS_EVERY
export BOOTSTRAP
export DATABASE
export TABLE
export BUCKETS

# Use envsubst to substitute variables in the YAML
envsubst < "${SCRIPT_DIR}/producer-job.yaml" | kubectl apply -f -

echo "  ✓ Producer job deployed"
echo ""

# Wait for job to be ready if requested
if [ "${WAIT_FOR_READY}" = true ]; then
    echo "[3/4] Waiting for producer pod to be ready..."
    if kubectl wait --for=condition=ready pod -l app=fluss-producer -n "${NAMESPACE}" --timeout=300s 2>/dev/null; then
        echo "  ✓ Producer pod is ready"
    else
        echo "  ⚠ Timeout waiting for producer pod to be ready"
        echo "  Check status: kubectl get pods -n ${NAMESPACE} -l app=fluss-producer"
    fi
    echo ""
fi

# Show job status
echo "[4/4] Producer job status:"
kubectl get job -n "${NAMESPACE}" fluss-producer
echo ""
kubectl get pods -n "${NAMESPACE}" -l app=fluss-producer
echo ""

# Show logs if requested
if [ "${SHOW_LOGS}" = true ]; then
    PRODUCER_POD=$(kubectl get pod -n "${NAMESPACE}" -l app=fluss-producer -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [ -n "${PRODUCER_POD}" ]; then
        echo "=== Producer Logs (last 50 lines) ==="
        kubectl logs -n "${NAMESPACE}" "${PRODUCER_POD}" --tail=50 || echo "  Could not retrieve logs"
        echo ""
    fi
fi

echo "=== Deployment Complete ==="
echo ""
echo "Monitor producer:"
echo "  kubectl get pods -n ${NAMESPACE} -l app=fluss-producer"
echo "  kubectl logs -n ${NAMESPACE} -l app=fluss-producer -f"
echo ""
echo "View producer metrics:"
echo "  kubectl port-forward -n ${NAMESPACE} svc/fluss-producer-metrics 8080:8080"
echo "  Then open: http://localhost:8080/metrics"
echo ""
echo "Delete producer job:"
echo "  kubectl delete job -n ${NAMESPACE} fluss-producer"
echo ""

