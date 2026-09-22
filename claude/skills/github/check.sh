#!/usr/bin/env bash
set -euo pipefail

echo "==> Checking gh CLI..."
if ! command -v gh &>/dev/null; then
  echo "❌ gh not found."
  echo "   macOS:  brew install gh"
  echo "   Linux:  https://github.com/cli/cli/blob/trunk/docs/install_linux.md"
  echo "   Docs:   https://cli.github.com/"
  exit 1
fi
echo "✅ $(gh --version | head -1)"

echo ""
echo "==> Checking gh auth status..."
if ! gh auth status &>/dev/null 2>&1; then
  echo "❌ gh not authenticated."
  echo "   Run: gh auth login"
  exit 1
fi
gh auth status 2>&1 | sed 's/^/   /'
echo "✅ Authenticated"

echo ""
echo "==> All checks passed. Ready to use gh CLI."
