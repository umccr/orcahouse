#!/usr/bin/env bash

set -euo pipefail

# NOTE:
# ECR repo is created by bastion_ecr stack else where.
# https://github.com/umccr/infrastructure/tree/master/terraform/stacks/bastion_ecr
# https://github.com/umccr/infrastructure/pull/540

AWS_PROFILE_BASTION=umccr-bastion-admin
REGION=ap-southeast-2

IMAGE_NAME=orcavault-dbt
IMAGE_URI=383856791668.dkr.ecr.${REGION}.amazonaws.com/${IMAGE_NAME}

echo "Building with ${AWS_PROFILE_BASTION} for ${IMAGE_URI}"
echo "------------------------------"
echo ""

aws ecr get-login-password --region ${REGION} --profile ${AWS_PROFILE_BASTION} | docker login --username AWS --password-stdin ${IMAGE_URI}

docker buildx build --platform linux/arm64 --provenance=false -t ${IMAGE_NAME} .
docker tag ${IMAGE_NAME}:latest ${IMAGE_URI}:latest
docker push ${IMAGE_URI}:latest

echo ""
echo "------------------------------"
echo "Done"
