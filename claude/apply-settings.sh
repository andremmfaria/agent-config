#!/usr/bin/env bash
set -euo pipefail

# claude/apply-settings.sh
# Injects the repo's settings.json `env` block into ~/.claude/settings.json,
# merging it into any existing settings rather than overwriting the file.
# This is how the auto effort level (CLAUDE_CODE_EFFORT_LEVEL=auto) reaches
# the live config: `auto` makes every model, including haiku subagents, use
# its own default effort instead of inheriting a forced session effortLevel
# that haiku cannot accept.
# Script lives one level under repo root (repo/claude/), so repo_root is "..".
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
dry_run=0

usage() {
  echo "Usage: $0 [--dry-run|-n]" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-n)
      dry_run=1
      shift
      ;;
    *)
      usage
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
src="$repo_root/claude/settings.json"
dst="$HOME/.claude/settings.json"

backup_base="${AGENT_CONFIG_BACKUP_DIR:-$HOME/.agent-config-backups}"
timestamp="$(date +%Y%m%d-%H%M%S)"
backup_root="$backup_base/$timestamp"

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  echo "[apply-settings/claude] ERROR: jq is required" >&2
  exit 1
fi

if [[ ! -f "$src" ]]; then
  echo "[apply-settings/claude] ERROR: source not found: $src" >&2
  exit 1
fi

# Pull the env block to inject from the repo settings.json.
src_env="$(jq -c '.env // {}' "$src")"
if [[ "$src_env" == "{}" ]]; then
  echo "[apply-settings/claude] WARNING: repo settings.json has no env block; nothing to inject" >&2
  exit 0
fi

# ---------------------------------------------------------------------------
# Merge env into the live settings.json (deep-merge env, keep everything else)
# ---------------------------------------------------------------------------
existing="{}"
[[ -f "$dst" ]] && existing="$(cat "$dst")"

merged="$(jq --argjson add "$src_env" '.env = ((.env // {}) + $add)' <<<"$existing")"

if [[ -f "$dst" ]] && [[ "$(jq -S . <<<"$existing")" == "$(jq -S . <<<"$merged")" ]]; then
  echo "[apply-settings/claude] unchanged settings.json"
  exit 0
fi

if [[ $dry_run -eq 1 ]]; then
  echo "[apply-settings/claude] would inject env into $dst:"
  echo "$src_env" | jq .
  exit 0
fi

mkdir -p "$(dirname "$dst")"
if [[ -f "$dst" ]]; then
  mkdir -p "$backup_root"
  cp -a "$dst" "$backup_root/claude-settings.json"
fi

printf '%s\n' "$merged" | jq . >"$dst"
echo "[apply-settings/claude] injected env into settings.json"
