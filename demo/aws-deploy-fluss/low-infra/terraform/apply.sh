#!/bin/bash
# Wrapper script for terraform apply that automatically imports existing ECR repositories
# Usage: ./apply.sh [terraform apply arguments]

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR"

# Run ECR import script first
echo "=== Pre-apply: Checking for existing ECR repositories ==="
"${SCRIPT_DIR}/import-ecr.sh"

echo ""
echo "=== Running terraform apply ==="
terraform apply "$@"

