#!/usr/bin/env bash
# Post-deploy test: wait for the rollout, then hit the live service.
# Usage: scripts/post_deploy_test.sh <deployment> <service> [namespace]
# Rolls back the deployment if either step fails.
set -euo pipefail

DEPLOYMENT="${1:?deployment name required}"
SERVICE="${2:?service name required}"
NAMESPACE="${3:-default}"

rollback() {
  echo "Post-deploy test failed, rolling back $DEPLOYMENT" >&2
  kubectl rollout undo "deployment/$DEPLOYMENT" -n "$NAMESPACE"
  kubectl rollout status "deployment/$DEPLOYMENT" -n "$NAMESPACE" --timeout=120s
  exit 1
}

echo "Waiting for rollout of $DEPLOYMENT ..."
kubectl rollout status "deployment/$DEPLOYMENT" -n "$NAMESPACE" --timeout=180s || rollback

# Get the external IP of the LoadBalancer service (wait up to ~3 min)
IP=""
for _ in $(seq 1 36); do
  IP=$(kubectl get svc "$SERVICE" -n "$NAMESPACE" \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [ -n "$IP" ] && break
  sleep 5
done
[ -n "$IP" ] || { echo "No external IP for service $SERVICE" >&2; rollback; }

echo "Checking http://$IP/health ..."
for _ in $(seq 1 12); do
  if body=$(curl -fsS --max-time 5 "http://$IP/health" 2>/dev/null) \
     && echo "$body" | grep -q '"status":"ok"\|"status": "ok"'; then
    echo "Post-deploy test passed: $body"
    exit 0
  fi
  sleep 5
done

rollback