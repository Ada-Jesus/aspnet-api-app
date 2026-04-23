#!/bin/bash
set -euo pipefail

# ================= REQUIRED ENV =================
: "${AWS_REGION:?Missing AWS_REGION}"
: "${ECS_CLUSTER:?Missing ECS_CLUSTER}"
: "${DEPLOY_SERVICE:?Missing DEPLOY_SERVICE}"

echo "================================================"
echo "🚀 ECS DEPLOYMENT START"
echo "Cluster: $ECS_CLUSTER"
echo "Service: $DEPLOY_SERVICE"
echo "Region:  $AWS_REGION"
echo "================================================"

# ================= DEPLOY =================

echo "==> Forcing new ECS deployment..."

aws ecs update-service \
  --cluster "$ECS_CLUSTER" \
  --service "$DEPLOY_SERVICE" \
  --force-new-deployment \
  --region "$AWS_REGION"

echo "==> Waiting for service stability..."

aws ecs wait services-stable \
  --cluster "$ECS_CLUSTER" \
  --services "$DEPLOY_SERVICE" \
  --region "$AWS_REGION"

echo "================================================"
echo "✅ DEPLOYMENT SUCCESSFUL"
echo "================================================"