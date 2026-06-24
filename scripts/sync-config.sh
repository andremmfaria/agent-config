#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dry_run=0

case "${1:-}" in
  "" ) ;;
  "--dry-run"|"-n" ) dry_run=1 ;;
  * )
    echo "Usage: $0 [--dry-run]" >&2
    exit 2
    ;;
esac

timestamp="$(date +%Y%m%d-%H%M%S)"
backup_base="${AGENT_CONFIG_BACKUP_DIR:-$HOME/.agent-config-backups}"
backup_root="$backup_base/$timestamp"

sha256_or_missing() {
  local path="$1"

  if [[ ! -e "$path" && ! -L "$path" ]]; then
    echo "MISSING"
    return
  fi

  if [[ -d "$path" ]]; then
    echo "DIRECTORY"
    return
  fi

  sha256sum "$path" | awk '{print $1}'
}

backup_path() {
  local src="$1"
  local label="$2"
  local relative="$3"

  if [[ ! -e "$src" && ! -L "$src" ]]; then
    return
  fi

  local dst="$backup_root/$label/$relative"

  if [[ $dry_run -eq 1 ]]; then
    echo "backup $src -> $dst"
    return
  fi

  mkdir -p "$(dirname "$dst")"
  cp -aL "$src" "$dst"
}

install_file() {
  local src="$1"
  local dst="$2"

  if [[ $dry_run -eq 1 ]]; then
    echo "copy $src -> $dst"
    return
  fi

  mkdir -p "$(dirname "$dst")"

  if [[ -L "$dst" ]]; then
    unlink "$dst"
  fi

  cp "$src" "$dst"
}

install_with_backup() {
  local src="$1"
  local dst="$2"
  local backup_label="$3"
  local relative="$4"

  backup_path "$dst" "$backup_label" "$relative"
  install_file "$src" "$dst"
}

choose_sync_direction() {
  local relative="$1"
  local reply

  if [[ $dry_run -eq 1 ]]; then
    echo "prompt"
    return
  fi

  if [[ -t 0 ]]; then
    while true; do
      {
        echo
        echo "Different live/repo file: $relative"
        echo "  [l] live wins: copy live -> repo (default)"
        echo "  [r] repo wins: copy repo -> live"
        echo "  [s] skip this file"
        printf "Choice [L/r/s]: "
      } >&2

      IFS= read -r reply || reply=""
      case "${reply,,}" in
        ""|"l"|"live")
          echo "live"
          return
          ;;
        "r"|"repo")
          echo "repo"
          return
          ;;
        "s"|"skip")
          echo "skip"
          return
          ;;
        *)
          echo "Invalid choice: $reply" >&2
          ;;
      esac
    done
  fi

  echo "different live/repo file, non-interactive default live -> repo: $relative" >&2
  echo "live"
}

sync_file() {
  local repo_path="$1"
  local live_path="$2"
  local relative="$3"

  local repo_hash live_hash action direction

  repo_hash="$(sha256_or_missing "$repo_path")"
  live_hash="$(sha256_or_missing "$live_path")"

  if [[ "$repo_hash" == "DIRECTORY" || "$live_hash" == "DIRECTORY" ]]; then
    echo "refuse directory: $relative" >&2
    exit 1
  fi

  if [[ "$repo_hash" == "MISSING" && "$live_hash" == "MISSING" ]]; then
    echo "missing both: $relative" >&2
    exit 1
  elif [[ "$repo_hash" == "MISSING" ]]; then
    action="live -> repo"
    install_file "$live_path" "$repo_path"
  elif [[ "$live_hash" == "MISSING" ]]; then
    action="repo -> live"
    install_file "$repo_path" "$live_path"
  elif [[ "$repo_hash" == "$live_hash" ]]; then
    action="same"
    if [[ -L "$live_path" ]]; then
      action="same, materialize live"
      install_with_backup "$repo_path" "$live_path" "live" "$relative"
    fi
  else
    direction="$(choose_sync_direction "$relative")"
    case "$direction" in
      "live")
        action="live -> repo"
        install_with_backup "$live_path" "$repo_path" "repo" "$relative"
        ;;
      "repo")
        action="repo -> live"
        install_with_backup "$repo_path" "$live_path" "live" "$relative"
        ;;
      "skip")
        action="skip"
        ;;
      "prompt")
        action="different, would prompt (default live -> repo)"
        ;;
      *)
        echo "unexpected sync direction for $relative: $direction" >&2
        exit 1
        ;;
    esac
  fi

  echo "$action: $relative"
}

sync_managed_files() {
  local file src agent_id

  # OpenClaw workspace files. USER.md, TOOLS.md, MEMORY.md, and daily notes stay private.
  for file in AGENTS.md SOUL.md IDENTITY.md HEARTBEAT.md; do
    sync_file \
      "$repo_root/openclaw/workspace/$file" \
      "$HOME/.openclaw/workspace/$file" \
      "openclaw/workspace/$file"
  done

  for src in "$repo_root"/openclaw/agents/*; do
    agent_id="$(basename "$src")"
    for file in AGENTS.md SOUL.md IDENTITY.md; do
      sync_file \
        "$src/$file" \
        "$HOME/.openclaw/agents/$agent_id/agent/$file" \
        "openclaw/agents/$agent_id/$file"
    done
  done

  sync_file "$repo_root/claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md" "claude/CLAUDE.md"
  sync_file \
    "$repo_root/claude/output-styles/orchestrator.md" \
    "$HOME/.claude/output-styles/orchestrator.md" \
    "claude/output-styles/orchestrator.md"

  for src in "$repo_root"/claude/agents/*.md; do
    sync_file \
      "$src" \
      "$HOME/.claude/agents/$(basename "$src")" \
      "claude/agents/$(basename "$src")"
  done
}

sync_managed_files

if [[ $dry_run -eq 0 ]]; then
  if [[ -d "$backup_root" ]]; then
    echo "backup: $backup_root"
  else
    echo "backup: none"
  fi
fi

# Apply agent definitions into each platform's live config.
# openclaw/apply-agents.sh: idempotent JSON upsert into ~/.openclaw/openclaw.json
# claude/apply-agents.sh:   copies *.md files into ~/.claude/agents/ (Claude Code
#                           reads agent definitions from markdown, not JSON)
apply_agents_flags=()
if [[ $dry_run -eq 1 ]]; then
  apply_agents_flags+=(--dry-run)
fi
bash "$repo_root/openclaw/apply-agents.sh" "${apply_agents_flags[@]}"
bash "$repo_root/claude/apply-agents.sh" "${apply_agents_flags[@]}"
