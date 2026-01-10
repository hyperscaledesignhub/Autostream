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

# Script to build and push images to ECR:
# 1. fluss-demo (for producer and flink aggregator)
# 2. fluss (Apache Fluss image)
#
# Usage:
#   ./high-infra/push-images-to-ecr.sh --all              # Push both images
#   ./high-infra/push-images-to-ecr.sh --producer-only    # Push only producer image
#   ./high-infra/push-images-to-ecr.sh --fluss-only       # Push only Fluss image
#
# IMPORTANT: This script must be run from the 2-million-messages-per-second directory

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# Get the 2-million-messages-per-second directory (parent of high-infra)
BASE_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
DEMO_DIR="${BASE_DIR}/fluss_flink_realtime"
AWS_REGION=${AWS_REGION:-us-west-2}
FLUSS_VERSION=${FLUSS_VERSION:-0.8.0-incubating}
ECR_INFO_FILE="${BASE_DIR}/ecr-repositories.txt"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Validate we're in the correct directory structure
if [ ! -d "${DEMO_DIR}" ]; then
    echo -e "${RED}Error: Cannot find fluss_flink_realtime directory${NC}"
    echo -e "${RED}Expected: ${DEMO_DIR}${NC}"
    echo -e "${RED}Please run this script from the 2-million-messages-per-second directory${NC}"
    exit 1
fi

# Validate we're running from 2-million-messages-per-second directory
EXPECTED_BASE_NAME="2-million-messages-per-second"
ACTUAL_BASE_NAME=$(basename "${BASE_DIR}")
if [ "${ACTUAL_BASE_NAME}" != "${EXPECTED_BASE_NAME}" ]; then
    echo -e "${RED}Error: Script must be run from the ${EXPECTED_BASE_NAME} directory${NC}"
    echo -e "${RED}Current directory: ${BASE_DIR}${NC}"
    echo -e "${RED}Please run: cd ${EXPECTED_BASE_NAME} && ./high-infra/push-images-to-ecr.sh${NC}"
    exit 1
fi

# Parse command line arguments
PUSH_DEMO=false
PUSH_FLUSS=false

case "${1:-}" in
    --all)
        PUSH_DEMO=true
        PUSH_FLUSS=true
        ;;
    --producer-only)
        PUSH_DEMO=true
        PUSH_FLUSS=false
        ;;
    --fluss-only)
        PUSH_DEMO=false
        PUSH_FLUSS=true
        ;;
    *)
        echo -e "${RED}Error: Missing or invalid argument${NC}"
        echo -e "Usage:"
        echo -e "  $0 --all            # Push both images"
        echo -e "  $0 --producer-only  # Push only producer image"
        echo -e "  $0 --fluss-only     # Push only Fluss image"
        exit 1
        ;;
esac

echo -e "${GREEN}=== Building and Pushing Images to ECR ===${NC}\n"
if [ "$PUSH_DEMO" = true ] && [ "$PUSH_FLUSS" = true ]; then
    echo -e "${YELLOW}Mode: Push both producer and Fluss images${NC}\n"
elif [ "$PUSH_DEMO" = true ]; then
    echo -e "${YELLOW}Mode: Push only producer image${NC}\n"
elif [ "$PUSH_FLUSS" = true ]; then
    echo -e "${YELLOW}Mode: Push only Fluss image${NC}\n"
fi

# Get AWS account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo -e "${RED}Error: Unable to get AWS account ID. Is AWS CLI configured?${NC}"
    exit 1
fi

ECR_BASE="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
DEMO_REPO="${ECR_BASE}/fluss-demo"
FLUSS_REPO="${ECR_BASE}/fluss"

echo -e "${YELLOW}AWS Account ID: ${AWS_ACCOUNT_ID}${NC}"
echo -e "${YELLOW}AWS Region: ${AWS_REGION}${NC}"
echo -e "${YELLOW}Demo Repository: ${DEMO_REPO}${NC}"
echo -e "${YELLOW}Fluss Repository: ${FLUSS_REPO}${NC}\n"

# Login to ECR
echo -e "${YELLOW}[1/5] Logging in to ECR...${NC}"
aws ecr get-login-password --region "${AWS_REGION}" | \
    docker login --username AWS --password-stdin "${ECR_BASE}"
echo -e "${GREEN}✓ Logged in to ECR${NC}\n"

# Ensure ECR repositories exist (they should be created by Terraform)
echo -e "${YELLOW}[2/5] Checking ECR repositories...${NC}"
if ! aws ecr describe-repositories --repository-names fluss-demo --region "${AWS_REGION}" >/dev/null 2>&1; then
    echo -e "${YELLOW}Creating fluss-demo repository...${NC}"
    aws ecr create-repository --repository-name fluss-demo --region "${AWS_REGION}" >/dev/null
fi
if ! aws ecr describe-repositories --repository-names fluss --region "${AWS_REGION}" >/dev/null 2>&1; then
    echo -e "${YELLOW}Creating fluss repository...${NC}"
    aws ecr create-repository --repository-name fluss --region "${AWS_REGION}" >/dev/null
fi
echo -e "${GREEN}✓ ECR repositories ready${NC}\n"

# Build and push producer application image
if [ "$PUSH_DEMO" = true ]; then
    echo -e "${YELLOW}[3/5] Building producer application image...${NC}"
    echo -e "${YELLOW}Step 1: Building JAR from source (clean build)...${NC}"
    cd "${DEMO_DIR}"
    mvn clean package
    JAR_FILE=$(find "${DEMO_DIR}/target" -name "fluss-flink-realtime-demo*.jar" -type f 2>/dev/null | head -1)
    if [ -z "${JAR_FILE}" ] || [ ! -f "${JAR_FILE}" ]; then
        echo -e "${RED}Error: JAR file not found after build${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ JAR built successfully: ${JAR_FILE}${NC}"
    echo ""

    cd "${DEMO_DIR}"
    echo -e "${YELLOW}Building Docker image for linux/amd64...${NC}"
    docker build --platform linux/amd64 -t fluss-demo:latest .
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    docker tag fluss-demo:latest "${DEMO_REPO}:latest"
    docker tag fluss-demo:latest "${DEMO_REPO}:${TIMESTAMP}"

    echo -e "${YELLOW}Pushing producer image to ECR...${NC}"
    docker push "${DEMO_REPO}:latest"
    docker push "${DEMO_REPO}:${TIMESTAMP}"
    echo -e "${GREEN}✓ Producer image pushed to ${DEMO_REPO}${NC}\n"
else
    echo -e "${YELLOW}[3/5] Skipping producer image (not requested)${NC}\n"
fi

# Pull, tag, and push Fluss image
if [ "$PUSH_FLUSS" = true ]; then
    echo -e "${YELLOW}[4/5] Pulling Apache Fluss image from Docker Hub (linux/amd64)...${NC}"
    FLUSS_IMAGE="apache/fluss:${FLUSS_VERSION}"
    docker pull --platform linux/amd64 "${FLUSS_IMAGE}"
    echo -e "${GREEN}✓ Fluss image pulled${NC}"

    echo -e "${YELLOW}Tagging Fluss image for ECR...${NC}"
    docker tag "${FLUSS_IMAGE}" "${FLUSS_REPO}:${FLUSS_VERSION}"
    docker tag "${FLUSS_IMAGE}" "${FLUSS_REPO}:latest"

    echo -e "${YELLOW}Pushing Fluss image to ECR...${NC}"
    docker push "${FLUSS_REPO}:${FLUSS_VERSION}"
    docker push "${FLUSS_REPO}:latest"
    echo -e "${GREEN}✓ Fluss image pushed to ${FLUSS_REPO}${NC}\n"
else
    echo -e "${YELLOW}[4/5] Skipping Fluss image (not requested)${NC}\n"
fi

# Summary
echo -e "${GREEN}=== Image Push Complete ===${NC}\n"
echo -e "Images pushed:"
if [ "$PUSH_DEMO" = true ]; then
    echo -e "  ${DEMO_REPO}:latest"
fi
if [ "$PUSH_FLUSS" = true ]; then
    echo -e "  ${FLUSS_REPO}:${FLUSS_VERSION}"
    echo -e "  ${FLUSS_REPO}:latest"
fi
echo -e ""

# Save ECR repository details to file
echo -e "${YELLOW}[5/5] Saving ECR repository details to ${ECR_INFO_FILE}...${NC}"
cat > "${ECR_INFO_FILE}" << EOF
# ECR Repository Details
# Generated on: $(date)
# AWS Account ID: ${AWS_ACCOUNT_ID}
# AWS Region: ${AWS_REGION}

EOF

if [ "$PUSH_DEMO" = true ]; then
    cat >> "${ECR_INFO_FILE}" << EOF
# Demo/Producer Image Repository
DEMO_IMAGE_REPOSITORY="${DEMO_REPO}"
DEMO_IMAGE_TAG="latest"

# For terraform.tfvars:
demo_image_repository = "${DEMO_REPO}"

EOF
fi

if [ "$PUSH_FLUSS" = true ]; then
    cat >> "${ECR_INFO_FILE}" << EOF
# Fluss Image Repository
FLUSS_IMAGE_REPOSITORY="${FLUSS_REPO}"
FLUSS_IMAGE_VERSION="${FLUSS_VERSION}"

# For terraform.tfvars:
fluss_image_repository = "${FLUSS_REPO}"
use_ecr_for_fluss = true

EOF
fi

cat >> "${ECR_INFO_FILE}" << EOF
# Full ECR Base URL
ECR_BASE="${ECR_BASE}"

# To use these values in shell scripts:
# source ${ECR_INFO_FILE}
# echo \${DEMO_IMAGE_REPOSITORY}
EOF

echo -e "${GREEN}✓ ECR repository details saved to ${ECR_INFO_FILE}${NC}"
echo -e ""
echo -e "To use these values:"
echo -e "  source ${ECR_INFO_FILE}"
echo -e ""
echo -e "Or update terraform.tfvars with:"
if [ "$PUSH_DEMO" = true ]; then
    echo -e "  demo_image_repository = \"${DEMO_REPO}\""
fi
if [ "$PUSH_FLUSS" = true ]; then
    echo -e "  fluss_image_repository = \"${FLUSS_REPO}\""
    echo -e "  use_ecr_for_fluss = true"
fi
echo -e ""

