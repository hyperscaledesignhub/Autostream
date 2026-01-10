#!/bin/bash
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

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

NAMESPACE="${NAMESPACE:-fluss}"

echo "=== Step 4: Verifying NVMe storage for tablet servers ==="
echo ""

# Check kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl is not installed or not in PATH"
    exit 1
fi

# Verify PersistentVolumes are using NVMe
echo "Checking PersistentVolumes..."
PV_COUNT=$(kubectl get pv -l component=tablet-server --no-headers 2>/dev/null | wc -l | awk '{print $1}')
if [ "${PV_COUNT}" -eq "0" ]; then
    echo "ERROR: No PersistentVolumes found for tablet servers"
    exit 1
fi

echo "✓ Found ${PV_COUNT} PersistentVolumes for tablet servers"
kubectl get pv -l component=tablet-server

# Check PV details for NVMe path
echo ""
echo "Verifying PV paths (should show /opt/alldata/fluss/data)..."
NVME_PVS=$(kubectl get pv -l component=tablet-server -o jsonpath='{.items[*].spec.local.path}' 2>/dev/null || echo "")
if echo "${NVME_PVS}" | grep -q "/opt/alldata/fluss/data"; then
    echo "✓ PVs are configured with NVMe paths"
else
    echo "WARNING: PV paths may not be configured correctly"
    kubectl get pv -l component=tablet-server -o yaml | grep -A 5 "path:" || true
fi

# Verify PVCs are bound
echo ""
echo "Checking PersistentVolumeClaims..."
PVC_COUNT=$(kubectl get pvc -n "${NAMESPACE}" --no-headers 2>/dev/null | wc -l | awk '{print $1}')
if [ "${PVC_COUNT}" -eq "0" ]; then
    echo "WARNING: No PersistentVolumeClaims found in namespace ${NAMESPACE}"
else
    echo "✓ Found ${PVC_COUNT} PersistentVolumeClaims"
    kubectl get pvc -n "${NAMESPACE}"
    
    # Check if PVCs are bound
    BOUND_COUNT=$(kubectl get pvc -n "${NAMESPACE}" -o jsonpath='{.items[?(@.status.phase=="Bound")].metadata.name}' 2>/dev/null | wc -w)
    if [ "${BOUND_COUNT}" -lt "${PVC_COUNT}" ]; then
        echo "WARNING: Not all PVCs are bound (${BOUND_COUNT}/${PVC_COUNT})"
    else
        echo "✓ All PVCs are bound"
    fi
fi

# Verify tablet server pods have volumes mounted
echo ""
echo "Checking tablet server pods..."
# Try multiple label selectors to find tablet server pods
TABLET_PODS=$(kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/component=tablet -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -z "${TABLET_PODS}" ]; then
    # Fallback: try finding pods by name pattern
    TABLET_PODS=$(kubectl get pods -n "${NAMESPACE}" -o jsonpath='{.items[?(@.metadata.name=~"tablet-server.*")].metadata.name}' 2>/dev/null || echo "")
fi

if [ -z "${TABLET_PODS}" ]; then
    echo "WARNING: No tablet server pods found"
    echo "  Attempted to find pods with label: app.kubernetes.io/component=tablet"
    echo "  Also tried to find pods matching pattern: tablet-server*"
    echo ""
    echo "  Available pods in namespace ${NAMESPACE}:"
    kubectl get pods -n "${NAMESPACE}" | grep -E "NAME|tablet" || kubectl get pods -n "${NAMESPACE}"
else
    echo "✓ Found tablet server pods:"
    kubectl get pods -n "${NAMESPACE}" -l app.kubernetes.io/component=tablet -o wide 2>/dev/null || \
    kubectl get pods -n "${NAMESPACE}" -o wide | grep tablet-server
    
    # Check first pod for volume mounts
    FIRST_POD=$(echo "${TABLET_PODS}" | awk '{print $1}')
    if [ -n "${FIRST_POD}" ]; then
        echo ""
        echo "Checking volume mounts in pod ${FIRST_POD}..."
        if kubectl exec -n "${NAMESPACE}" "${FIRST_POD}" -- df -h | grep -q "alldata"; then
            echo "✓ NVMe storage is mounted in tablet server pod"
            kubectl exec -n "${NAMESPACE}" "${FIRST_POD}" -- df -h | grep "alldata"
        else
            echo "WARNING: NVMe storage may not be mounted correctly"
        fi
    fi
fi

echo ""
echo "✓ Step 4 completed: NVMe storage verification completed"

