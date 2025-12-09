#!/bin/bash
set -euo pipefail

# Script to download Fluss Helm chart
# The chart will be downloaded and extracted to helm-charts/fluss directory

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HELM_CHARTS_DIR="${SCRIPT_DIR}/helm-charts"
FLUSS_VERSION=${FLUSS_VERSION:-0.8.0-incubating}
CHART_URL="https://downloads.apache.org/incubator/fluss/helm-chart/fluss-${FLUSS_VERSION}.tgz"

echo "Downloading Fluss Helm chart version ${FLUSS_VERSION}..."

# Create helm-charts directory if it doesn't exist
mkdir -p "${HELM_CHARTS_DIR}"

# Download chart
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

cd "${TEMP_DIR}"
curl -L -o "fluss-${FLUSS_VERSION}.tgz" "${CHART_URL}"

# Extract chart
tar -xzf "fluss-${FLUSS_VERSION}.tgz"

# Copy to helm-charts directory
if [ -d "fluss" ]; then
    rm -rf "${HELM_CHARTS_DIR}/fluss"
    cp -r "fluss" "${HELM_CHARTS_DIR}/"
    echo "✓ Fluss Helm chart extracted to ${HELM_CHARTS_DIR}/fluss"
else
    echo "Error: Chart extraction failed"
    exit 1
fi

echo "Chart download complete!"

