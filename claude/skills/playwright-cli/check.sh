#!/usr/bin/env bash
set -euo pipefail

echo "==> Checking playwright-cli..."
if ! pw_version=$(npx @playwright/cli --version 2>/dev/null); then
  echo "❌ npx @playwright/cli --version failed."
  echo "   Install globally: npm install -g @playwright/cli@latest"
  echo "   Or let npx fetch it on demand (first run downloads the package)."
  exit 1
fi
echo "✅ playwright-cli $pw_version"

echo ""
echo "==> Checking installed browsers..."
# install-browser --list is read-only: prints known playwright installs, no download.
browser_list=$(npx @playwright/cli install-browser --list 2>&1)
if ! echo "$browser_list" | grep -q "Browsers:"; then
  echo "❌ Could not read browser install state."
  echo "   Run: npx @playwright/cli install-browser"
  exit 1
fi
browser_dirs=$(echo "$browser_list" | sed -n '/Browsers:/,/References:/p' | grep -E '^\s+/' || true)
if [[ -z "$browser_dirs" ]]; then
  echo "❌ No browsers installed."
  echo "   Run: npx @playwright/cli install-browser"
  exit 1
fi
echo "✅ Browsers installed:"
while read -r line; do
  echo "   $line"
done <<< "$browser_dirs"

echo ""
echo "==> All checks passed. Ready to use playwright-cli."
