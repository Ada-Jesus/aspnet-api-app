#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════
#  health_check.sh  –  Poll /health via ALB test listener (8080)
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

: "${ALB_DNS_NAME:?Missing ALB_DNS_NAME}"

URL="http://${ALB_DNS_NAME}/health"

echo "==> Checking health: $URL"

for i in {1..10}; do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "$URL" || echo "000")

  if [ "$CODE" = "200" ]; then
    echo "==> Healthy"
    exit 0
  fi

  echo "Attempt $i failed ($CODE)"
  sleep 5
done

echo "ERROR: service unhealthy"
exit 1
