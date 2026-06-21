#!/usr/bin/env bash
set -euo pipefail

# claude/apply-agents.sh
# Copies Claude agent markdown files from the repo into ~/.claude/agents/.
# Claude Code reads agent definitions from markdown files only, not from JSON.
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
src_dir="$repo_root/claude/agents"
dst_dir="$HOME/.claude/agents"

backup_base="${AGENT_CONFIG_BACKUP_DIR:-$HOME/.agent-config-backups}"
timestamp="$(date +%Y%m%d-%H%M%S)"
backup_root="$backup_base/$timestamp"

# ---------------------------------------------------------------------------
# Install agent markdown files
# ---------------------------------------------------------------------------
install_agents() {
  local src dst label

  if [[ ! -d "$src_dir" ]]; then
    echo "[apply-agents/claude] ERROR: source directory not found: $src_dir" >&2
    exit 1
  fi

  shopt -s nullglob
  local files=("$src_dir"/*.md)
  shopt -u nullglob

  if [[ ${#files[@]} -eq 0 ]]; then
    echo "[apply-agents/claude] WARNING: no *.md files found in $src_dir" >&2
    return
  fi

  if [[ $dry_run -eq 0 ]]; then
    mkdir -p "$dst_dir"
  fi

  for src in "${files[@]}"; do
    local fname
    fname="$(basename "$src")"
    dst="$dst_dir/$fname"

    if [[ $dry_run -eq 1 ]]; then
      echo "copy $src -> $dst"
    else
      # Back up existing destination file before overwriting
      if [[ -f "$dst" ]]; then
        label="claude-agents/$fname"
        local bak="$backup_root/$label"
        mkdir -p "$(dirname "$bak")"
        cp -a "$dst" "$bak"
      fi
      cp "$src" "$dst"
      echo "[apply-agents/claude] installed $fname"
    fi
  done
}

install_agents
