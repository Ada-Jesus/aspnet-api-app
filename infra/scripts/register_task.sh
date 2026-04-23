#!/bin/bash
set -euo pipefail

: "${IMAGE_URI:?Missing IMAGE_URI}"
: "${AWS_REGION:?Missing AWS_REGION}"
: "${ECS_CLUSTER:?Missing ECS_CLUSTER}"
: "${DEPLOY_SERVICE:?Missing DEPLOY_SERVICE}"

echo "==> Updating ECS service with new image..."

TASK_DEF_ARN=$(aws ecs describe-task-definition \
  --task-definition "$DEPLOY_SERVICE" \
  --query "taskDefinition.taskDefinitionArn" \
  --output text \
  --region "$AWS_REGION")

echo "Using task definition: $TASK_DEF_ARN"

echo "==> Updating service with force new deployment..."

aws ecs update-service \
  --cluster "$ECS_CLUSTER" \
  --service "$DEPLOY_SERVICE" \
  --force-new-deployment \
  --region "$AWS_REGION"

echo "DONE"