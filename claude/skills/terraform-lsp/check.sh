#!/usr/bin/env bash
set -euo pipefail

PLUGIN_JSON="$HOME/.claude/skills/terraform-lsp/.claude-plugin/plugin.json"

echo "==> Checking terraform-ls on PATH..."
if ! command -v terraform-ls &>/dev/null; then
  echo "❌ terraform-ls not found."
  echo "   Install: https://github.com/hashicorp/terraform-ls#installation"
  echo "   Or via a release binary placed on PATH (e.g. ~/.local/bin/terraform-ls)."
  exit 1
fi
echo "✅ terraform-ls $(terraform-ls --version 2>&1 | head -1)"

echo ""
echo "==> Checking plugin.json..."
if [[ ! -f "$PLUGIN_JSON" ]]; then
  echo "❌ plugin.json not found at $PLUGIN_JSON"
  exit 1
fi
if ! server_cmd=$(python3 -c "
import json
with open('$PLUGIN_JSON') as f:
    data = json.load(f)
print(data['lspServers']['terraform-ls']['command'])
" 2>/dev/null); then
  echo "❌ plugin.json does not parse or is missing lspServers.terraform-ls"
  exit 1
fi
echo "✅ plugin.json parses, declares terraform-ls server (command: $server_cmd)"

echo ""
echo "==> Checking terraform-ls starts on stdio..."
# serve reads LSP requests from stdin, closing stdin (EOF) makes it shut down
# cleanly on its own, so a short timeout is just a safety net, not the trigger.
smoke_log=$(timeout 2 terraform-ls serve </dev/null 2>&1 || true)
if ! echo "$smoke_log" | grep -q "Starting terraform-ls"; then
  echo "❌ terraform-ls serve did not start cleanly."
  while IFS= read -r line; do
    echo "   $line"
  done <<< "$smoke_log"
  exit 1
fi
echo "✅ terraform-ls serve starts and accepts stdio"

echo ""
echo "==> All checks passed. Ready to use terraform-lsp."
