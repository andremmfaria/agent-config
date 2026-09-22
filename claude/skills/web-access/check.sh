#!/usr/bin/env bash
set -euo pipefail

available=0

echo "==> Checking Layer 1 (WebFetch / WebSearch)..."
echo "✅ Always available (built-in tools, no local dependency)"
available=$((available + 1))

echo ""
echo "==> Checking Layer 2 (playwright-cli)..."
if [[ -d "$HOME/.claude/skills/playwright-cli" ]] && npx @playwright/cli --version &>/dev/null; then
  echo "✅ playwright-cli skill present, $(npx @playwright/cli --version 2>/dev/null | head -1)"
  available=$((available + 1))
else
  echo "⚠️  playwright-cli unavailable."
  echo "   Install: npx -y @playwright/cli@latest install --skills --global"
fi

echo ""
echo "==> Checking Layer 3 (Fortress)..."
if ! command -v tilion-fortress &>/dev/null; then
  echo "⚠️  tilion-fortress not found."
  echo "   Install: uv tool install tilion-fortress"
else
  echo "✅ $(tilion-fortress --version 2>&1 | head -1)"
  # upstream ships the bundle as tillion-fortress/tillion while the loader wants tilion-fortress/tilion
  broken=0
  for dir in "$HOME"/.cache/tilion-fortress/*/linux-x64; do
    [[ -d "$dir" ]] || continue
    if [[ -d "$dir/tillion-fortress" && ! -e "$dir/tilion-fortress/tilion" ]]; then
      broken=1
      echo "⚠️  Launcher name mismatch in $(basename "$(dirname "$dir")"), known upstream bug."
      echo "   Fix: ln -sfn '$dir/tillion-fortress' '$dir/tilion-fortress'"
      echo "        ln -sfn '$dir/tillion-fortress/tillion' '$dir/tillion-fortress/tilion'"
    fi
  done
  [[ $broken -eq 0 ]] && available=$((available + 1))
fi

echo ""
if [[ $available -eq 0 ]]; then
  echo "❌ No layer is usable."
  exit 1
fi
echo "==> All checks passed. Ready to use web-access ($available/3 layers available)."
