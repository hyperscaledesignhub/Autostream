#!/bin/bash
# Script to create PersistentVolumes for Fluss tablet servers using local NVMe storage
# This script generates PVs based on the number of tablet server replicas

set -e

NAMESPACE="${NAMESPACE:-fluss}"
TABLET_REPLICAS="${TABLET_REPLICAS:-3}"
STORAGE_SIZE="${STORAGE_SIZE:-500Gi}"

echo "Creating PersistentVolumes for Fluss tablet servers..."
echo "  Namespace: ${NAMESPACE}"
echo "  Replicas: ${TABLET_REPLICAS}"
echo "  Storage Size: ${STORAGE_SIZE}"

for i in $(seq 0 $((TABLET_REPLICAS - 1))); do
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: fluss-tablet-data-${i}
  labels:
    type: local-nvme
    component: tablet-server
    storage-type: data
    app: fluss
spec:
  capacity:
    storage: ${STORAGE_SIZE}
  accessModes:
    - ReadWriteOnce
  storageClassName: local-storage
  local:
    path: /opt/alldata/fluss
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: fluss-component
              operator: In
              values:
                - tablet-server
            - key: storage-type
              operator: In
              values:
                - nvme
  persistentVolumeReclaimPolicy: Retain
EOF
  echo "  ✓ Created PV: fluss-tablet-data-${i}"
done

echo ""
echo "PersistentVolumes created successfully!"
echo "Verify with: kubectl get pv -l component=tablet-server"

