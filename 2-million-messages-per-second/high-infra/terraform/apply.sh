#!/bin/bash
# Wrapper script for terraform apply
# Usage: ./apply.sh [terraform apply arguments]
#
# Note: ECR repositories are no longer managed by Terraform.
# Create them manually via AWS CLI/Console and set repository URLs in terraform.tfvars

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR"

echo "=== Running terraform apply ==="
terraform apply "$@"

