#!/usr/bin/env bash
set -euo pipefail

echo "==> Checking acli (Atlassian CLI)..."
if ! command -v acli &>/dev/null; then
  echo "❌ acli not found."
  echo "   macOS:  brew install atlassian/tap/acli"
  echo "   Linux:  Download binary from https://developer.atlassian.com/cloud/acli/guides/how-to-get-started/"
  echo "   Docs:   https://developer.atlassian.com/cloud/acli/"
  exit 1
fi
echo "✅ acli $(acli --version 2>/dev/null | head -1 || echo 'installed')"

echo ""
echo "==> Checking curl (required for Confluence — not covered by acli)..."
if ! command -v curl &>/dev/null; then
  echo "❌ curl not found. Install via your package manager."
  exit 1
fi
echo "✅ curl $(curl --version | head -1)"

echo ""
echo "==> Checking confpub-cli (primary tool for markdown → Confluence)..."
if ! command -v confpub &>/dev/null; then
  echo "⚠️  confpub not found (fallback to pandoc+curl will be used)."
  echo "   Install: pip install confpub-cli"
  echo "   Docs:    https://github.com/ThomasRohde/confpub-cli"
else
  echo "✅ $(confpub --version 2>/dev/null | head -1 || echo 'confpub installed')"
fi

echo ""
echo "==> Checking pandoc (fallback for markdown → Confluence conversion)..."
if ! command -v pandoc &>/dev/null; then
  echo "⚠️  pandoc not found (fallback unavailable — confpub required)."
  echo "   macOS:  brew install pandoc"
  echo "   Linux:  sudo apt install pandoc  (or download from https://github.com/jgm/pandoc/releases)"
  echo "   Docs:   https://pandoc.org/installing.html"
else
  echo "✅ $(pandoc --version | head -1)"
fi

echo ""
echo "==> Checking env vars..."
missing=()
[[ -z "${ATLASSIAN_EMAIL:-}" ]]     && missing+=("ATLASSIAN_EMAIL")
[[ -z "${ATLASSIAN_API_TOKEN:-}" ]] && missing+=("ATLASSIAN_API_TOKEN")
[[ -z "${ATLASSIAN_BASE_URL:-}" ]]  && missing+=("ATLASSIAN_BASE_URL")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "❌ Missing env vars: ${missing[*]}"
  exit 1
fi
echo "✅ ATLASSIAN_EMAIL=${ATLASSIAN_EMAIL}"
echo "✅ ATLASSIAN_API_TOKEN set"
echo "✅ ATLASSIAN_BASE_URL=${ATLASSIAN_BASE_URL}"

echo ""
echo "==> Checking acli auth..."
SITE=$(echo "$ATLASSIAN_BASE_URL" | sed 's|https\?://||')
if ! acli jira auth status &>/dev/null 2>&1; then
  echo "⚠️  acli not authenticated. Run:"
  echo "   echo \"\$ATLASSIAN_API_TOKEN\" | acli jira auth login --site \"${SITE}\" --email \"${ATLASSIAN_EMAIL}\" --token"
else
  echo "✅ acli authenticated"
fi

echo ""
echo "==> All checks passed. Ready to use acli (Jira) + confpub (Confluence, primary) + pandoc+curl (Confluence, fallback)."
