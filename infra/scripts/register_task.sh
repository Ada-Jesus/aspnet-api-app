#!/bin/bash
set -euo pipefail

: "${IMAGE_URI:?Missing IMAGE_URI}"
: "${AWS_REGION:?Missing AWS_REGION}"

echo "==> Registering new task definition..."

# ALWAYS use repo root safe path
TASK_DEF_FILE="infra/terraform/task-definition.json"

if [ ! -f "$TASK_DEF_FILE" ]; then
  echo "❌ Task definition file not found at: $TASK_DEF_FILE"
  ls -R infra || true
  exit 1
fi

TASK_DEF_JSON=$(cat "$TASK_DEF_FILE")

NEW_TASK_DEF=$(echo "$TASK_DEF_JSON" | jq \
  --arg IMAGE "$IMAGE_URI" \
  '.containerDefinitions[0].image = $IMAGE
  | del(
      .taskDefinitionArn,
      .revision,
      .status,
      .requiresAttributes,
      .compatibilities,
      .registeredAt,
      .registeredBy
    )')

TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json "$NEW_TASK_DEF" \
  --query "taskDefinition.taskDefinitionArn" \
  --output text \
  --region "$AWS_REGION")

echo "==> Registered task definition:"
echo "$TASK_DEF_ARN"

echo "TASK_DEF_ARN=$TASK_DEF_ARN" >> $GITHUB_ENV