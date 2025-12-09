#!/bin/bash
# Setup script for local NVMe storage for Fluss tablet servers
# This script creates the StorageClass and PersistentVolumes needed for local storage

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="${NAMESPACE:-fluss}"
TABLET_REPLICAS="${TABLET_REPLICAS:-3}"
STORAGE_SIZE="${STORAGE_SIZE:-500Gi}"

echo "=========================================="
echo "Setting up Local NVMe Storage for Fluss"
echo "=========================================="
echo ""

# Step 1: Create StorageClass
echo "[1/3] Creating StorageClass for local storage..."
kubectl apply -f "${SCRIPT_DIR}/local-storage-class.yaml"
echo "  ✓ StorageClass 'local-storage' created"
echo ""

# Step 2: Delete existing PVs if they exist (for idempotency)
echo "[2/3] Cleaning up existing PersistentVolumes (if any)..."
kubectl delete pv -l component=tablet-server,type=local-nvme --ignore-not-found=true
echo "  ✓ Cleanup completed"
echo ""

# Step 3: Create PersistentVolumes
echo "[3/3] Creating PersistentVolumes for ${TABLET_REPLICAS} tablet server(s)..."
export NAMESPACE TABLET_REPLICAS STORAGE_SIZE
"${SCRIPT_DIR}/create-local-pvs.sh"
echo ""

echo "=========================================="
echo "Local Storage Setup Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "  1. Verify StorageClass: kubectl get storageclass local-storage"
echo "  2. Verify PVs: kubectl get pv -l component=tablet-server"
echo "  3. Deploy Fluss with:"
echo "     - persistence.enabled: true"
echo "     - persistence.storageClass: local-storage"
echo "     - persistence.size: ${STORAGE_SIZE}"
echo ""

