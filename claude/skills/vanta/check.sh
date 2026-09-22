#!/usr/bin/env bash
set -euo pipefail

echo "==> Checking curl..."
if ! command -v curl &>/dev/null; then
  echo "❌ curl not found. Install via your package manager."
  exit 1
fi
echo "✅ curl $(curl --version | head -1)"

echo ""
echo "==> Checking python3 (required for token extraction)..."
if ! command -v python3 &>/dev/null; then
  echo "❌ python3 not found. Install via your package manager."
  exit 1
fi
echo "✅ python3 $(python3 --version)"

echo ""
echo "==> Checking env vars..."
missing=()
[[ -z "${VANTA_BASE:-}" ]]          && missing+=("VANTA_BASE")
[[ -z "${VANTA_CLIENT_ID:-}" ]]     && missing+=("VANTA_CLIENT_ID")
[[ -z "${VANTA_CLIENT_SECRET:-}" ]] && missing+=("VANTA_CLIENT_SECRET")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "❌ Missing env vars: ${missing[*]}"
  echo "   VANTA_BASE          — e.g. https://api.vanta.com"
  echo "   VANTA_CLIENT_ID     — OAuth client ID from Vanta developer settings"
  echo "   VANTA_CLIENT_SECRET — OAuth client secret from Vanta developer settings"
  exit 1
fi
echo "✅ VANTA_BASE=${VANTA_BASE}"
echo "✅ VANTA_CLIENT_ID set"
echo "✅ VANTA_CLIENT_SECRET set"

echo ""
echo "==> Validating OAuth token fetch..."
token_response=$(curl -s -L -X POST "$VANTA_BASE/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=$VANTA_CLIENT_ID&client_secret=$VANTA_CLIENT_SECRET&scope=vanta-api.all:read")

token=$(echo "$token_response" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('access_token',''))" 2>/dev/null || echo "")
if [[ -z "$token" ]]; then
  echo "❌ Failed to obtain OAuth token. Check VANTA_CLIENT_ID and VANTA_CLIENT_SECRET."
  echo "   Response: $token_response"
  exit 1
fi
echo "✅ OAuth token obtained successfully"

echo ""
echo "==> All checks passed. Ready to use curl with Vanta API."
