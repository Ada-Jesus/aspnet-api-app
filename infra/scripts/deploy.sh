#!/bin/bash
set -euo pipefail

echo "==> Starting stable blue/green deployment"

# ───────────────────────── SAFE CHECKS ─────────────────────────
if [ -z "${IMAGE_URI:-}" ]; then
  echo "ERROR: IMAGE_URI missing"
  exit 1
fi

if [ -z "${ECS_CLUSTER:-}" ]; then
  echo "ERROR: ECS_CLUSTER missing"
  exit 1
fi

if [ -z "${BLUE_SERVICE:-}" ]; then
  echo "ERROR: BLUE_SERVICE missing"
  exit 1
fi

if [ -z "${GREEN_SERVICE:-}" ]; then
  echo "ERROR: GREEN_SERVICE missing"
  exit 1
fi


# ───────────────────────── DETECT SLOT ─────────────────────────
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


# ───────────────────────── TASK DEF UPDATE ─────────────────────────
TASK_DEF_ARN=$(aws ecs describe-task-definition \
  --task-definition aspnet-api-production \
  --query "taskDefinition.taskDefinitionArn" \
  --output text)

RAW=$(aws ecs describe-task-definition \
  --task-definition "$TASK_DEF_ARN")

UPDATED=$(echo "$RAW" | jq \
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
  --cli-input-json "$UPDATED" \
  --query "taskDefinition.taskDefinitionArn" \
  --output text)

echo "Task Def: $NEW_TASK_DEF"


# ───────────────────────── DEPLOY ─────────────────────────
aws ecs update-service \
  --cluster "$ECS_CLUSTER" \
  --service "$DEPLOY" \
  --task-definition "$NEW_TASK_DEF" \
  --desired-count 1 \
  --force-new-deployment \
  --region "${AWS_REGION:-us-east-1}"

aws ecs wait services-stable \
  --cluster "$ECS_CLUSTER" \
  --services "$DEPLOY"


# ───────────────────────── HEALTH CHECK ─────────────────────────
ALB="${ALB_DNS_NAME:-}"

if [ -z "$ALB" ]; then
  echo "No ALB → skipping health check"
else
  URL="http://$ALB/health"

  for i in {1..10}; do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "$URL" || echo "000")

    if [ "$CODE" = "200" ]; then
      echo "Healthy"
      break
    fi

    echo "Attempt $i failed ($CODE)"
    sleep 5

    if [ "$i" -eq 10 ]; then
      echo "ROLLBACK TRIGGERED"
      aws ecs update-service \
        --cluster "$ECS_CLUSTER" \
        --service "$DEPLOY" \
        --desired-count 0
      exit 1
    fi
  done
fi


# ───────────────────────── TRAFFIC SWITCH ─────────────────────────
aws elbv2 modify-listener \
  --listener-arn "$ALB_LISTENER_ARN" \
  --default-actions "Type=forward,TargetGroupArn=${DEPLOY_TG_ARN}"


# ───────────────────────── SCALE DOWN OLD SLOT ─────────────────────────
aws ecs update-service \
  --cluster "$ECS_CLUSTER" \
  --service "$LIVE" \
  --desired-count 0

echo "==> Deployment complete"