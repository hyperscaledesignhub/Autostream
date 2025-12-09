#!/bin/bash
# Script to automatically import existing ECR repositories into Terraform state
# This runs before terraform apply to prevent RepositoryAlreadyExistsException errors

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR"

AWS_REGION=${AWS_REGION:-us-west-2}

echo "Checking for existing ECR repositories to import..."

# Check and import fluss-demo repository
if aws ecr describe-repositories --repository-names fluss-demo --region "${AWS_REGION}" >/dev/null 2>&1; then
  echo "Found existing fluss-demo repository, checking state..."
    if terraform state show aws_ecr_repository.demo_app >/dev/null 2>&1; then
    echo "  ✓ fluss-demo already in Terraform state"
    else
    echo "  → Importing fluss-demo into Terraform state..."
    if terraform import aws_ecr_repository.demo_app fluss-demo 2>&1; then
      echo "  ✓ Successfully imported fluss-demo"
    else
      echo "  ⚠ Warning: Could not import fluss-demo (will try to create, may fail if exists)"
    fi
  fi
else
  echo "  ℹ fluss-demo repository does not exist, will be created"
fi

# Check and import fluss repository
if aws ecr describe-repositories --repository-names fluss --region "${AWS_REGION}" >/dev/null 2>&1; then
  echo "Found existing fluss repository, checking state..."
    if terraform state show aws_ecr_repository.fluss >/dev/null 2>&1; then
    echo "  ✓ fluss already in Terraform state"
    else
    echo "  → Importing fluss into Terraform state..."
    if terraform import aws_ecr_repository.fluss fluss 2>&1; then
      echo "  ✓ Successfully imported fluss"
    else
      echo "  ⚠ Warning: Could not import fluss (will try to create, may fail if exists)"
    fi
  fi
else
  echo "  ℹ fluss repository does not exist, will be created"
fi

echo "ECR import check complete."

