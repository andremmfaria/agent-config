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
state_dir="$repo_root/.sync-state"
state_file="$state_dir/managed-files.tsv"
next_state="$(mktemp)"

declare -A previous_hashes=()

if [[ -f "$state_file" ]]; then
  while IFS=$'\t' read -r key hash; do
    [[ -n "${key:-}" ]] || continue
    previous_hashes["$key"]="$hash"
  done < "$state_file"
fi

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

sync_file() {
  local repo_path="$1"
  local live_path="$2"
  local relative="$3"
  local key="$relative"

  local repo_hash live_hash base_hash action final_hash

  repo_hash="$(sha256_or_missing "$repo_path")"
  live_hash="$(sha256_or_missing "$live_path")"
  base_hash="${previous_hashes[$key]:-}"

  if [[ "$repo_hash" == "DIRECTORY" || "$live_hash" == "DIRECTORY" ]]; then
    echo "refuse directory: $relative" >&2
    exit 1
  fi

  backup_path "$repo_path" "repo" "$relative"
  backup_path "$live_path" "live" "$relative"

  if [[ "$repo_hash" == "MISSING" && "$live_hash" == "MISSING" ]]; then
    echo "missing both: $relative" >&2
    exit 1
  elif [[ "$repo_hash" == "MISSING" ]]; then
    action="local -> repo"
    install_file "$live_path" "$repo_path"
  elif [[ "$live_hash" == "MISSING" ]]; then
    action="repo -> local"
    install_file "$repo_path" "$live_path"
  elif [[ "$repo_hash" == "$live_hash" ]]; then
    action="same"
    if [[ -L "$live_path" ]]; then
      action="same, materialize local"
      install_file "$repo_path" "$live_path"
    fi
  elif [[ -z "$base_hash" ]]; then
    action="conflict, local -> repo"
    install_file "$live_path" "$repo_path"
  elif [[ "$repo_hash" != "$base_hash" && "$live_hash" == "$base_hash" ]]; then
    action="repo -> local"
    install_file "$repo_path" "$live_path"
  elif [[ "$repo_hash" == "$base_hash" && "$live_hash" != "$base_hash" ]]; then
    action="local -> repo"
    install_file "$live_path" "$repo_path"
  else
    action="conflict, local -> repo"
    install_file "$live_path" "$repo_path"
  fi

  final_hash="$(sha256_or_missing "$repo_path")"
  if [[ $dry_run -eq 0 ]]; then
    printf '%s\t%s\n' "$key" "$final_hash" >> "$next_state"
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
  mkdir -p "$state_dir"
  sort "$next_state" > "$state_file"
  rm -f "$next_state"
  echo "backup: $backup_root"
else
  rm -f "$next_state"
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
