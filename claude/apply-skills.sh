#!/usr/bin/env bash
set -euo pipefail

# claude/apply-skills.sh
# Copies Claude Code skill directories from claude/skills/ in this repo into
# ~/.claude/skills/. Claude Code reads skills exclusively from directories
# under ~/.claude/skills/, each containing a SKILL.md (or, for a plugin
# masquerading as a skill directory, a .claude-plugin/plugin.json).
#
# This script is additive and updating only: it never deletes a live skill
# directory that has no counterpart in the repo, and it never deletes files
# inside a live skill directory that are not tracked in the repo copy (this
# matters for vendored, gitignored dependencies such as atlassian's
# node_modules, which must survive every apply run untouched). It only adds
# or overwrites files that exist in the repo's copy of a skill.
#
# The synced/ directory is harness-managed, not a user skill, and is never
# read from the repo (it is gitignored) or written to the live directory.
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
src_dir="$repo_root/claude/skills"
dst_dir="$HOME/.claude/skills"

backup_base="${AGENT_CONFIG_BACKUP_DIR:-$HOME/.agent-config-backups}"
timestamp="$(date +%Y%m%d-%H%M%S)"
backup_root="$backup_base/$timestamp"

# Never sync this name in either direction: it is the harness-managed
# directory, not a user skill.
skip_name="synced"

# ---------------------------------------------------------------------------
# Tree manifest: relative-path -> sha256, restricted to the files that exist
# in a given directory. Used to compare only the files the repo tracks for a
# skill, so live-only vendored files (node_modules, __pycache__, ...) never
# count toward the unchanged/changed decision and are never touched.
# ---------------------------------------------------------------------------
manifest() {
  local dir="$1"
  (cd "$dir" && find . -type f -print0 | sort -z | xargs -0 sha256sum)
}

# Returns 0 (unchanged) when every file tracked in src_skill has an identical
# sha256 at the same relative path under dst_skill, and dst_skill has no
# other differences for those paths. Extra dst-only files are ignored.
skill_unchanged() {
  local src_skill="$1" dst_skill="$2"
  local rel hash dst_hash

  [[ -d "$dst_skill" ]] || return 1

  while IFS= read -r line; do
    hash="${line%% *}"
    rel="${line#* }"
    rel="${rel# }"
    rel="${rel#./}"
    if [[ ! -f "$dst_skill/$rel" ]]; then
      return 1
    fi
    dst_hash="$(sha256sum "$dst_skill/$rel" | awk '{print $1}')"
    if [[ "$dst_hash" != "$hash" ]]; then
      return 1
    fi
  done < <(manifest "$src_skill")

  return 0
}

# Copies every file tracked under src_skill into dst_skill, creating
# directories as needed. Never removes anything already present in
# dst_skill, so live-only vendored files survive untouched.
copy_skill() {
  local src_skill="$1" dst_skill="$2"
  local rel

  while IFS= read -r -d '' rel; do
    rel="${rel#./}"
    mkdir -p "$(dirname "$dst_skill/$rel")"
    cp "$src_skill/$rel" "$dst_skill/$rel"
  done < <(cd "$src_skill" && find . -type f -print0)
}

# ---------------------------------------------------------------------------
# Install skill directories
# ---------------------------------------------------------------------------
install_skills() {
  local src_skill dst_skill skill_name

  if [[ ! -d "$src_dir" ]]; then
    echo "[apply-skills/claude] ERROR: source directory not found: $src_dir" >&2
    exit 1
  fi

  shopt -s nullglob
  local dirs=("$src_dir"/*/)
  shopt -u nullglob

  if [[ ${#dirs[@]} -eq 0 ]]; then
    echo "[apply-skills/claude] WARNING: no skill directories found in $src_dir" >&2
    return
  fi

  if [[ $dry_run -eq 0 ]]; then
    mkdir -p "$dst_dir"
  fi

  for src_skill in "${dirs[@]}"; do
    src_skill="${src_skill%/}"
    skill_name="$(basename "$src_skill")"

    if [[ "$skill_name" == "$skip_name" ]]; then
      echo "[apply-skills/claude] skipped $skill_name (harness-managed, never synced)"
      continue
    fi

    dst_skill="$dst_dir/$skill_name"

    if skill_unchanged "$src_skill" "$dst_skill"; then
      echo "[apply-skills/claude] unchanged $skill_name"
      continue
    fi

    if [[ $dry_run -eq 1 ]]; then
      echo "copy $src_skill -> $dst_skill"
      continue
    fi

    # Back up the whole live skill directory before overwriting any of it.
    if [[ -d "$dst_skill" ]]; then
      local bak="$backup_root/claude-skills/$skill_name"
      mkdir -p "$(dirname "$bak")"
      cp -a "$dst_skill" "$bak"
    fi

    copy_skill "$src_skill" "$dst_skill"
    echo "[apply-skills/claude] installed $skill_name"
  done
}

install_skills
