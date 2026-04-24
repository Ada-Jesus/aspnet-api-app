#!/bin/bash
set -euo pipefail

: "${AWS_REGION:?Missing AWS_REGION}"
: "${ECS_CLUSTER:?Missing ECS_CLUSTER}"
: "${BLUE_SERVICE:?Missing BLUE_SERVICE}"
: "${GREEN_SERVICE:?Missing GREEN_SERVICE}"
: "${IMAGE_URI:?Missing IMAGE_URI}"

echo "==> Starting stable blue/green deployment"

# ───────────────────────────────
# STEP 1: Detect active slot
# ───────────────────────────────
BLUE_COUNT=$(aws ecs describe-services \
  --cluster "$ECS_CLUSTER" \
  --services "$BLUE_SERVICE" \
  --query "services[0].desiredCount" \
  --output text)

if [ "$BLUE_COUNT" -gt 0 ]; then
  LIVE="$BLUE_SERVICE"
  DEPLOY="$GREEN_SERVICE"
else
  LIVE="$GREEN_SERVICE"
  DEPLOY="$BLUE_SERVICE"
fi

echo "Live: $LIVE"
echo "Deploy: $DEPLOY"

# ───────────────────────────────
# STEP 2: Create new task definition
# ───────────────────────────────
TASK_DEF_ARN=$(aws ecs describe-task-definition \
  --task-definition aspnet-api-production \
  --query "taskDefinition.taskDefinitionArn" \
  --output text)

RAW_TASK_DEF=$(aws ecs describe-task-definition \
  --task-definition "$TASK_DEF_ARN")

UPDATED_TASK_DEF=$(echo "$RAW_TASK_DEF" | jq \
  --arg IMAGE "$IMAGE_URI" \
  '.taskDefinition
  | .containerDefinitions[0].image = $IMAGE
  | del(
      .taskDefinitionArn,
      .revision,
      .status,
      .requiresAttributes,
      .compatibilities,
      .registeredAt,
      .registeredBy
    )')

NEW_TASK_DEF=$(aws ecs register-task-definition \
  --cli-input-json "$UPDATED_TASK_DEF" \
  --query "taskDefinition.taskDefinitionArn" \
  --output text)

echo "New Task Def: $NEW_TASK_DEF"

# ───────────────────────────────
# STEP 3: Deploy to standby slot
# ───────────────────────────────
aws ecs update-service \
  --cluster "$ECS_CLUSTER" \
  --service "$DEPLOY" \
  --task-definition "$NEW_TASK_DEF" \
  --desired-count "${DESIRED_COUNT:-1}" \
  --force-new-deployment \
  --region "$AWS_REGION"

aws ecs wait services-stable \
  --cluster "$ECS_CLUSTER" \
  --services "$DEPLOY"

# ───────────────────────────────
# STEP 4: Health check
# ───────────────────────────────
ALB_DNS="${ALB_DNS_NAME:-}"

if [ -z "$ALB_DNS" ]; then
  echo "No ALB DNS → skipping health check"
  exit 0
fi

URL="http://${ALB_DNS}/health"

for i in {1..10}; do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "$URL" || echo "000")

  if [ "$CODE" = "200" ]; then
    echo "Healthy"
    break
  fi

  echo "Attempt $i failed ($CODE)"
  sleep 5

  if [ "$i" -eq 10 ]; then
    echo "FAILED → rolling back"
    aws ecs update-service \
      --cluster "$ECS_CLUSTER" \
      --service "$DEPLOY" \
      --desired-count 0
    exit 1
  fi
done

# ───────────────────────────────
# STEP 5: Switch traffic
# ───────────────────────────────
aws elbv2 modify-listener \
  --listener-arn "$ALB_LISTENER_ARN" \
  --default-actions "Type=forward,TargetGroupArn=${DEPLOY_TG_ARN}"

# ───────────────────────────────
# STEP 6: Scale down old slot
# ───────────────────────────────
aws ecs update-service \
  --cluster "$ECS_CLUSTER" \
  --service "$LIVE" \
  --desired-count 0

echo "Deployment complete"