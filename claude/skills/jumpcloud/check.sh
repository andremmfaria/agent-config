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
if [[ -z "${JUMPCLOUD_API_KEY:-}" ]]; then
  echo "❌ Missing env var: JUMPCLOUD_API_KEY"
  echo "   JUMPCLOUD_API_KEY — admin API key from JumpCloud console (avatar → My API Key)"
  echo "   Load it: export JUMPCLOUD_API_KEY=\$(secret-tool lookup service jumpcloud key JUMPCLOUD_API_KEY)"
  exit 1
fi
echo "✅ JUMPCLOUD_API_KEY set"

echo ""
echo "==> Validating API key..."
status=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "x-api-key: $JUMPCLOUD_API_KEY" \
  "https://console.jumpcloud.com/api/systemusers?limit=1")
if [[ "$status" != "200" ]]; then
  echo "❌ Auth check failed (HTTP $status). Verify JUMPCLOUD_API_KEY."
  exit 1
fi
echo "✅ API key valid (HTTP 200)"

echo ""
echo "==> All checks passed. Ready to use curl with JumpCloud API."
