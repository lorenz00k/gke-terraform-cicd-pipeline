#!/usr/bin/env bash
# Post-deploy test: wait for the rollout, then hit the live service.
# Usage: tests/post_deploy_test.sh <deployment> <service> [namespace]
#
# Env:
#   LOCAL=1       reach the service via kubectl port-forward (kind/minikube)
#                 instead of the LoadBalancer's external IP
#   ROLLBACK=0    don't roll back on failure (default: 1)
set -euo pipefail

DEPLOYMENT="${DEPLOYMENT:?deployment name required}"
SERVICE="${SERVICE:?service name required}"
NAMESPACE="${NAMESPACE:-default}"
LOCAL="${LOCAL:-0}"
ROLLBACK="${ROLLBACK:-1}"

fail() {
  echo "Post-deploy test failed: $DEPLOYMENT" >&2
  if ["$ROLLOUT" = "1"]; then
    echo "Rolling back $DEPLOYMENT" >&2
    kubectl rollout undo "deployment/$DEPLOYMENT" -n "$NAMESPACE"
    kubectl rollout status "deployment/$DEPLOYMENT" -n "$NAMESPACE" --timeout=120s
  fi
  exit 1
}

echo "Waiting for rollout of $DEPLOYMENT ..."
kubectl rollout status "deployment/$DEPLOYMENT" -n "$NAMESPACE" --timeout=180s || fail "Rollout did not complete"

if ["$LOCAL" = "1"]; then
  PORT=$(kubectl get svc "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].port}')
  kubectl port-forward "svc/$SERVICE" 8080:"$PORT" -n "$NAMESPACE" >/dev/null 2>&1 &
  PF_PID=$!
  HOST="localhost:8080"
else
  # Get the external IP of the LoadBalancer service (wait up to ~3 min)
  HOST=""
  for _ in $(seq 1 36); do
    HOST=$(kubectl get svc "$SERVICE" -n "$NAMESPACE" \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    [ -n "$HOST" ] && break
    sleep 5
  done
  [ -n "$HOST" ] || { echo "No external IP for service $SERVICE" >&2; }
fi

echo "Checking http://$HOST/health ..."
for _ in $(seq 1 12); do
  if body=$(curl -fsS --max-time 5 "http://$HOST/health" 2>/dev/null) \
     && echo "$body" | grep -q '"status":"ok"\|"status": "ok"'; then
    echo "Post-deploy test passed: $body"
    exit 0
  fi
  sleep 5
done

fail "/health did not return ok"