#!/usr/bin/env bash
# E2E smoke test for v2 API (no Agent required).
set -euo pipefail

BASE="${BASE:-http://127.0.0.1:8080}"
TOKEN="${TOKEN:-}"

auth=()
if [ -n "$TOKEN" ]; then
  auth=(-H "Authorization: Bearer $TOKEN")
fi

json() { jq -r . 2>/dev/null || cat; }

echo "== health =="
curl -fsS "$BASE/api/v1/health" | json

echo "== create machine =="
MACHINE=$(curl -fsS "${auth[@]}" -H 'Content-Type: application/json' \
  -d '{"name":"e2e-nat-1","role":"nat-transit"}' \
  "$BASE/api/v2/machines")
MACHINE_ID=$(echo "$MACHINE" | jq -r '.data.id // .id')
echo "machine_id=$MACHINE_ID"

echo "== create profile =="
PROFILE=$(curl -fsS "${auth[@]}" -H 'Content-Type: application/json' \
  -d "{\"name\":\"e2e-line\",\"machine_id\":\"$MACHINE_ID\",\"config\":{\"LANDING_HOST\":\"1.2.3.4\"}}" \
  "$BASE/api/v2/profiles")
PROFILE_ID=$(echo "$PROFILE" | jq -r '.data.profile.id // .profile.id')
echo "profile_id=$PROFILE_ID"

echo "== sync profile (3 tasks) =="
SYNC=$(curl -fsS "${auth[@]}" -H 'Content-Type: application/json' \
  -d '{}' "$BASE/api/v2/profiles/$PROFILE_ID/sync")
TASK_ID=$(echo "$SYNC" | jq -r '.data.tasks[0].id // .tasks[0].id')
echo "task_id=$TASK_ID"

echo "== task SSE (first event) =="
curl -fsS -N "${auth[@]}" -H 'Accept: text/event-stream' \
  "$BASE/api/v2/tasks/$TASK_ID/stream" | head -n 5

echo "== bootstrap install command =="
curl -fsS "${auth[@]}" -H 'Content-Type: application/json' \
  -d "{\"machine_id\":\"$MACHINE_ID\"}" \
  "$BASE/api/v2/bootstrap/install" | jq -r '.data.root_command // .root_command' | head -n 3

echo "E2E smoke OK"
