#!/usr/bin/env bash
set -euo pipefail

echo "==> Checking octopus CLI..."
if ! command -v octopus &>/dev/null; then
  echo "❌ octopus CLI not found."
  echo "   macOS:  brew install octopusdeploy/taps/octopus-cli"
  echo "   Linux:  https://octopus.com/downloads/octopuscli"
  echo "   Docs:   https://octopus.com/docs/octopus-rest-api/cli"
  exit 1
fi
echo "✅ $(octopus version 2>/dev/null | head -1 || echo 'installed')"

echo ""
echo "==> Checking env vars..."
missing=()
[[ -z "${OCTOPUS_URL:-}" ]]     && missing+=("OCTOPUS_URL")
[[ -z "${OCTOPUS_API_KEY:-}" ]] && missing+=("OCTOPUS_API_KEY")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "❌ Missing env vars: ${missing[*]}"
  echo "   OCTOPUS_URL     — e.g. https://your-instance.octopus.app"
  echo "   OCTOPUS_API_KEY — API key from Octopus → Profile → API Keys"
  exit 1
fi
echo "✅ OCTOPUS_URL=${OCTOPUS_URL}"
echo "✅ OCTOPUS_API_KEY set"

echo ""
echo "==> Validating connection..."
if ! octopus space list &>/dev/null 2>&1; then
  echo "❌ Could not connect. Verify OCTOPUS_URL and OCTOPUS_API_KEY."
  exit 1
fi
echo "✅ Connection verified"

echo ""
echo "==> All checks passed. Ready to use octopus CLI."
