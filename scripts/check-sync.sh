#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0

sha256_or_missing() {
  local path="$1"

  if [[ ! -e "$path" && ! -L "$path" ]]; then
    echo "MISSING"
    return
  fi

  sha256sum "$path" | awk '{print $1}'
}

check_file() {
  local repo_path="$1"
  local live_path="$2"
  local relative="$3"
  local repo_hash live_hash

  repo_hash="$(sha256_or_missing "$repo_path")"
  live_hash="$(sha256_or_missing "$live_path")"

  if [[ "$repo_hash" == "MISSING" || "$live_hash" == "MISSING" ]]; then
    echo "missing: $relative"
    fail=1
    return
  fi

  if [[ -L "$live_path" ]]; then
    echo "still symlink: $live_path"
    fail=1
    return
  fi

  if [[ "$repo_hash" != "$live_hash" ]]; then
    echo "differs: $relative"
    fail=1
    return
  fi

  echo "ok: $relative"
}

for file in AGENTS.md SOUL.md IDENTITY.md HEARTBEAT.md; do
  check_file \
    "$repo_root/openclaw/workspace/$file" \
    "$HOME/.openclaw/workspace/$file" \
    "openclaw/workspace/$file"
done

for src in "$repo_root"/openclaw/agents/*; do
  agent_id="$(basename "$src")"
  for file in AGENTS.md SOUL.md IDENTITY.md; do
    check_file \
      "$src/$file" \
      "$HOME/.openclaw/agents/$agent_id/agent/$file" \
      "openclaw/agents/$agent_id/$file"
  done
done

check_file "$repo_root/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md" "claude/CLAUDE.md"
check_file \
  "$repo_root/claude/output-styles/orchestrator.md" \
  "$HOME/.claude/output-styles/orchestrator.md" \
  "claude/output-styles/orchestrator.md"

for src in "$repo_root"/claude/agents/*.md; do
  check_file \
    "$src" \
    "$HOME/.claude/agents/$(basename "$src")" \
    "claude/agents/$(basename "$src")"
done

exit "$fail"
