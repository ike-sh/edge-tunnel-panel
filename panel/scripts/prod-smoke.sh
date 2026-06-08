#!/usr/bin/env bash
# Production-mode smoke: strict_auth=true requires OPERATOR_TOKEN.
set -euo pipefail

BASE="${BASE:-http://127.0.0.1:18080}"
TOKEN="${OPERATOR_TOKEN:?set OPERATOR_TOKEN}"

auth=(-H "Authorization: Bearer $TOKEN")

echo "== health (expect strict_auth=true) =="
curl -fsS "${auth[@]}" "$BASE/api/v1/health" | jq .

echo "== create machine (auth required) =="
curl -fsS "${auth[@]}" -H 'Content-Type: application/json' \
  -d '{"name":"prod-nat-1","role":"nat-transit"}' \
  "$BASE/api/v2/machines" | jq .

echo "== unauthorized should fail =="
code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/v2/machines")
test "$code" = "401" && echo "401 OK" || echo "expected 401, got $code"

echo "prod smoke OK"
