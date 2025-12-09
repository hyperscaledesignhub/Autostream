#!/bin/bash
set -euo pipefail

# Script to build and push images to ECR:
# 1. fluss-demo (for producer and flink aggregator)
# 2. fluss (Apache Fluss image)
#
# Usage:
#   ./push-images-to-ecr.sh --all              # Push both images
#   ./push-images-to-ecr.sh --producer-only    # Push only producer image
#   ./push-images-to-ecr.sh --fluss-only       # Push only Fluss image

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEMO_DIR="${SCRIPT_DIR}/../../demos/demo/fluss_flink_realtime_demo"
AWS_REGION=${AWS_REGION:-us-west-2}
FLUSS_VERSION=${FLUSS_VERSION:-0.8.0-incubating}

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

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
    if [ ! -f "${DEMO_DIR}/target/fluss-flink-realtime-demo.jar" ]; then
        echo -e "${YELLOW}Building JAR...${NC}"
        cd "${DEMO_DIR}"
        mvn clean package
    else
        echo -e "${GREEN}JAR already exists${NC}"
    fi

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
echo -e "Update terraform.tfvars with:"
if [ "$PUSH_DEMO" = true ]; then
    echo -e "  demo_image_repository = \"${DEMO_REPO}\""
fi
if [ "$PUSH_FLUSS" = true ]; then
    echo -e "  fluss_image_repository = \"${FLUSS_REPO}\""
    echo -e "  use_ecr_for_fluss = true"
fi
echo -e ""

