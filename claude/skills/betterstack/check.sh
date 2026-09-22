#!/usr/bin/env bash
set -euo pipefail

echo "==> Checking curl..."
if ! command -v curl &>/dev/null; then
  echo "❌ curl not found. Install via your package manager."
  exit 1
fi
echo "✅ curl $(curl --version | head -1)"

echo ""
echo "==> Checking env vars..."
missing=()
[[ -z "${BETTERSTACK_TOKEN:-}" ]]     && missing+=("BETTERSTACK_TOKEN")
[[ -z "${BETTERSTACK_UPTIME:-}" ]]    && missing+=("BETTERSTACK_UPTIME")
[[ -z "${BETTERSTACK_TELEMETRY:-}" ]] && missing+=("BETTERSTACK_TELEMETRY")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "❌ Missing env vars: ${missing[*]}"
  echo "   BETTERSTACK_TOKEN      — API token from Better Stack → API tokens"
  echo "   BETTERSTACK_UPTIME     — e.g. https://uptime.betterstack.com/api/v3"
  echo "   BETTERSTACK_TELEMETRY  — e.g. https://telemetry.betterstack.com/api/v1"
  exit 1
fi
echo "✅ BETTERSTACK_TOKEN set"
echo "✅ BETTERSTACK_UPTIME=${BETTERSTACK_UPTIME}"
echo "✅ BETTERSTACK_TELEMETRY=${BETTERSTACK_TELEMETRY}"

echo ""
echo "==> Validating token..."
status=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $BETTERSTACK_TOKEN" \
  "$BETTERSTACK_UPTIME/monitors?per_page=1")
if [[ "$status" != "200" ]]; then
  echo "❌ Auth check failed (HTTP $status). Verify BETTERSTACK_TOKEN."
  exit 1
fi
echo "✅ Token valid (HTTP 200)"

echo ""
echo "==> All checks passed. Ready to use curl with BetterStack API."
