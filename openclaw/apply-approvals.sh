#!/usr/bin/env bash
set -euo pipefail

# openclaw/apply-approvals.sh
# Idempotent merge of repo exec-approvals policy (openclaw/exec-approvals.json:
# defaults + agents) into ~/.openclaw/exec-approvals.json, preserving the
# live file's `socket` (IPC path + auth token, never committed) and `version`.
# After writing, prints `openclaw approvals get` so the effective policy
# change is visible immediately.
# Script lives one level under repo root (repo/openclaw/), so repo_root is "..".
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
live_approvals="$HOME/.openclaw/exec-approvals.json"
repo_approvals="$repo_root/openclaw/exec-approvals.json"

backup_base="${AGENT_CONFIG_BACKUP_DIR:-$HOME/.agent-config-backups}"
timestamp="$(date +%Y%m%d-%H%M%S)"
backup_root="$backup_base/$timestamp"

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  echo "[apply-approvals/openclaw] ERROR: jq is required" >&2
  exit 1
fi

if [[ ! -f "$repo_approvals" ]]; then
  echo "[apply-approvals/openclaw] ERROR: repo file not found: $repo_approvals" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Helper: backup a file (no-op in dry-run)
# ---------------------------------------------------------------------------
backup_file() {
  local src="$1"
  local label="$2"

  if [[ ! -f "$src" ]]; then
    return
  fi

  if [[ $dry_run -eq 1 ]]; then
    echo "# [apply-approvals/openclaw] backup $src -> $backup_root/$label" >&2
    return
  fi

  local dst="$backup_root/$label"
  mkdir -p "$(dirname "$dst")"
  cp -a "$src" "$dst"
}

# ---------------------------------------------------------------------------
# Merge
# ---------------------------------------------------------------------------
apply_approvals() {
  local base_json

  if [[ -f "$live_approvals" ]]; then
    base_json="$(cat "$live_approvals")"
  else
    echo "# [apply-approvals/openclaw] WARNING: $live_approvals not found; using empty base" >&2
    base_json='{"version":1,"socket":{},"defaults":{},"agents":{}}'
  fi

  # Replace .defaults and .agents wholesale from the repo file; keep live
  # .socket and .version untouched (repo never carries the live token, and
  # the live install owns the schema version).
  local repo_defaults repo_agents
  repo_defaults="$(jq -c '.defaults // {}' "$repo_approvals")"
  repo_agents="$(jq -c '.agents // {}' "$repo_approvals")"

  local merged
  merged="$(
    jq \
      --argjson repo_defaults "$repo_defaults" \
      --argjson repo_agents "$repo_agents" \
      '. + { defaults: $repo_defaults, agents: $repo_agents }' \
      <<< "$base_json"
  )"

  if [[ $dry_run -eq 1 ]]; then
    echo "# ===== apply-approvals dry-run: exec-approvals ====="
    echo "$merged"
    return
  fi

  if [[ -f "$live_approvals" ]] && printf '%s\n' "$merged" | cmp -s - "$live_approvals"; then
    echo "[apply-approvals/openclaw] unchanged $live_approvals"
    return
  fi

  backup_file "$live_approvals" "exec-approvals.json"
  printf '%s\n' "$merged" > "$live_approvals"
  chmod 600 "$live_approvals" 2>/dev/null || true
  echo "[apply-approvals/openclaw] wrote $live_approvals"
}

apply_approvals

# ---------------------------------------------------------------------------
# Show effective policy (skip in dry-run: nothing changed on disk to reflect)
# ---------------------------------------------------------------------------
if [[ $dry_run -eq 0 ]]; then
  echo
  echo "# ===== effective policy (openclaw approvals get) ====="
  openclaw approvals get
fi
