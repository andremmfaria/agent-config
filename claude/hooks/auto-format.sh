#!/usr/bin/env bash
# Layer: style
# PostToolUse / Write|Edit|MultiEdit auto-formatter (port of opencode's
# `file.changed` recommended use). Best-effort: formats the just-touched file
# with the right tool IF that tool is installed, else stays silent. Never blocks,
# never fails the turn (no `set -e`: a formatter's non-zero exit is swallowed).
set -uo pipefail

payload="$(cat)"
file="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null)"
[ -z "$file" ] && exit 0
[ -f "$file" ] || exit 0

have() { command -v "$1" >/dev/null 2>&1; }
fmt=""

case "$file" in
  *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.json|*.jsonc|*.css|*.scss|*.less|*.html|*.vue|*.svelte|*.yaml|*.yml|*.md|*.markdown|*.graphql)
      if have prettier; then prettier --write --log-level silent "$file" >/dev/null 2>&1 && fmt="prettier"
      elif have npx; then npx --no-install prettier --write --log-level silent "$file" >/dev/null 2>&1 && fmt="prettier"; fi ;;
  *.py)
      if have ruff; then ruff format -q "$file" >/dev/null 2>&1 && fmt="ruff"
      elif have black; then black -q "$file" >/dev/null 2>&1 && fmt="black"; fi ;;
  *.go)        if have gofmt;   then gofmt -w "$file"               >/dev/null 2>&1 && fmt="gofmt";   fi ;;
  *.rs)        if have rustfmt; then rustfmt "$file"               >/dev/null 2>&1 && fmt="rustfmt"; fi ;;
  *.sh|*.bash) if have shfmt;   then shfmt -w "$file"              >/dev/null 2>&1 && fmt="shfmt";   fi ;;
  *.rb)        if have rubocop; then rubocop -A -f quiet "$file"   >/dev/null 2>&1 && fmt="rubocop"; fi ;;
esac

[ -z "$fmt" ] && exit 0
jq -n --arg f "${file##*/}" --arg t "$fmt" \
  '{systemMessage: ("auto-format: " + $f + " formatted with " + $t), suppressOutput: true}' 2>/dev/null || true
exit 0
