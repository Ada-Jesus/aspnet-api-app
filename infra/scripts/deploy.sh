#!/bin/bash
set -euo pipefail

: "${ECS_CLUSTER:?Missing ECS_CLUSTER}"
: "${DEPLOY_SERVICE:?Missing DEPLOY_SERVICE}"
: "${TASK_DEF_ARN:?Missing TASK_DEF_ARN}"

echo "==> Updating ECS service..."

aws ecs update-service \
  --cluster "$ECS_CLUSTER" \
  --service "$DEPLOY_SERVICE" \
  --task-definition "$TASK_DEF_ARN" \
  --force-new-deployment \
  --region "${AWS_REGION:-us-east-1}"

echo "==> Waiting for stability..."

aws ecs wait services-stable \
  --cluster "$ECS_CLUSTER" \
  --services "$DEPLOY_SERVICE"

echo "==> Deployment successful"