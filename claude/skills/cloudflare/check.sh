#!/usr/bin/env bash
set -euo pipefail

echo "==> Checking flarectl..."
if ! command -v flarectl &>/dev/null; then
  echo "❌ flarectl not found."
  echo "   Install: go install github.com/cloudflare/cloudflare-go/cmd/flarectl@latest"
  echo "        or: Download binary from https://github.com/cloudflare/cloudflare-go/releases"
  echo "   Docs: https://github.com/cloudflare/cloudflare-go/tree/master/cmd/flarectl"
  exit 1
fi
echo "✅ flarectl $(flarectl --version 2>/dev/null | head -1 || echo 'installed')"

echo ""
echo "==> Checking curl (required for Workers — not covered by flarectl)..."
if ! command -v curl &>/dev/null; then
  echo "❌ curl not found. Install via your package manager."
  exit 1
fi
echo "✅ curl $(curl --version | head -1)"

echo ""
echo "==> Checking env vars..."
missing=()
[[ -z "${CLOUDFLARE_INVESTIGATION_TOKEN:-}" ]] && missing+=("CLOUDFLARE_INVESTIGATION_TOKEN")
[[ -z "${CLOUDFLARE_ACCOUNT:-}" ]]             && missing+=("CLOUDFLARE_ACCOUNT")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "❌ Missing env vars: ${missing[*]}"
  echo "   flarectl uses CF_API_TOKEN — set it inline:"
  echo "   CF_API_TOKEN=\$CLOUDFLARE_INVESTIGATION_TOKEN flarectl zone list"
  exit 1
fi
echo "✅ CLOUDFLARE_INVESTIGATION_TOKEN set (read + write)"
echo "✅ CLOUDFLARE_ACCOUNT=${CLOUDFLARE_ACCOUNT}"

echo ""
echo "==> All checks passed. Ready to use flarectl (DNS/zones) + curl (Workers)."
