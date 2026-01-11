#!/bin/zsh
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION="us-west-2"
export DEMO_IMAGE_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/fluss-demo"
export DEMO_IMAGE_TAG="latest"
export FLUSS_IMAGE_REPO="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/fluss"
export NAMESPACE="fluss"
export CLUSTER_NAME="fluss-eks-cluster"
export REGION="${AWS_REGION}"
