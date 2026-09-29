#!/usr/bin/env bash
# Smoke test: start the built image and check that it answers on /health.
# Usage: scripts/smoke_test.sh <image>   (default: gke-demo-app:ci)
set -euo pipefail

IMAGE="${1:-gke-demo-app:ci}"
NAME="smoke-test-$$"
HOST_PORT="${HOST_PORT:-18080}"

cleanup() {
  docker logs "$NAME" 2>&1 | tail -n 20 || true
  docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker run -d --name "$NAME" -p "${HOST_PORT}:8080" "$IMAGE" >/dev/null

echo "Waiting for /health ..."
for _ in $(seq 1 30); do
  if body=$(curl -fsS "http://localhost:${HOST_PORT}/health" 2>/dev/null); then
    echo "Response: $body"
    if echo "$body" | grep -q '"status":"ok"\|"status": "ok"'; then
      echo "Smoke test passed."
      exit 0
    fi
    echo "Unexpected /health body" >&2
    exit 1
  fi
  sleep 1
done

echo "Smoke test failed: /health did not respond within 30s" >&2
exit 1