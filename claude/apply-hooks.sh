#!/usr/bin/env bash
set -euo pipefail

# claude/apply-hooks.sh
# Installs ALL hard-layer hooks from repo/claude/hooks/ into ~/.claude/hooks/
# and merges every hook entry from repo/claude/settings.json's `hooks` block
# into ~/.claude/settings.json, idempotently. Hooks are the out-of-band gate:
# they inspect the tool call itself, not the model's reasoning, so prompt
# injection cannot talk its way past them.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

dry_run=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|-n) dry_run=1; shift ;;
    *) echo "Usage: $0 [--dry-run|-n]" >&2; exit 2 ;;
  esac
done

src_dir="$repo_root/claude/hooks"
dst_dir="$HOME/.claude/hooks"
repo_settings="$repo_root/claude/settings.json"
settings="$HOME/.claude/settings.json"
backup_base="${AGENT_CONFIG_BACKUP_DIR:-$HOME/.agent-config-backups}"
backup_root="$backup_base/$(date +%Y%m%d-%H%M%S)"

command -v jq >/dev/null || { echo "[apply-hooks/claude] ERROR: jq required" >&2; exit 1; }

# 1. Copy all hook scripts.
shopt -s nullglob
for src in "$src_dir"/*.sh; do
  fname="$(basename "$src")"; dst="$dst_dir/$fname"
  if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
    echo "[apply-hooks/claude] unchanged $fname"; continue
  fi
  if [[ $dry_run -eq 1 ]]; then echo "copy $src -> $dst"; continue; fi
  mkdir -p "$dst_dir"
  if [[ -f "$dst" ]]; then mkdir -p "$backup_root/claude-hooks"; cp -a "$dst" "$backup_root/claude-hooks/$fname"; fi
  cp "$src" "$dst"; chmod +x "$dst"
  echo "[apply-hooks/claude] installed $fname"
done
shopt -u nullglob

# 2. Merge every hook entry from repo claude/settings.json .hooks into the
#    live settings.json, idempotently: an entry is added only if the same
#    (expanded) command string is not already present under that event.
#    ~ is expanded to $HOME at install time (repo settings.json is a template
#    using ~, live settings.json uses $HOME-form paths).
[[ -f "$repo_settings" ]] || { echo "[apply-hooks/claude] ERROR: $repo_settings not found" >&2; exit 1; }
repo_json="$(cat "$repo_settings")"
merged="{}"; [[ -f "$settings" ]] && merged="$(cat "$settings")"
original="$merged"

events="$(jq -r '.hooks // {} | keys[]' <<<"$repo_json")"
for event in $events; do
  ngroups="$(jq -r --arg e "$event" '.hooks[$e] | length' <<<"$repo_json")"
  for ((gi = 0; gi < ngroups; gi++)); do
    matcher="$(jq -r --arg e "$event" --argjson gi "$gi" '.hooks[$e][$gi].matcher // empty' <<<"$repo_json")"
    nhooks="$(jq -r --arg e "$event" --argjson gi "$gi" '.hooks[$e][$gi].hooks | length' <<<"$repo_json")"
    for ((hi = 0; hi < nhooks; hi++)); do
      hookobj="$(jq -c --arg e "$event" --argjson gi "$gi" --argjson hi "$hi" '.hooks[$e][$gi].hooks[$hi]' <<<"$repo_json")"
      cmd="$(jq -r '.command' <<<"$hookobj")"
      cmd_expanded="${cmd//\~/\$HOME}"
      hookobj_expanded="$(jq -c --arg c "$cmd_expanded" '.command = $c' <<<"$hookobj")"

      # Compare with $HOME normalized to its literal runtime value on both
      # sides: a pre-existing entry may have been written with the real home
      # path baked in (not the $HOME token this script writes going forward),
      # and without normalizing, that entry and our $HOME-form candidate would
      # look like different commands and register a duplicate hook.
      already="$(jq -r --arg e "$event" --arg c "$cmd_expanded" --arg home "$HOME" '
        ($c | gsub("\\$HOME"; $home)) as $cn |
        ([(.hooks[$e] // [])[]?.hooks[]?.command] | map(gsub("\\$HOME"; $home))) as $existing_n |
        ($existing_n | index($cn)) != null
      ' <<<"$merged")"
      if [[ "$already" == "true" ]]; then
        echo "[apply-hooks/claude] already wired $event${matcher:+/$matcher} -> $cmd_expanded"
        continue
      fi

      if [[ $dry_run -eq 1 ]]; then
        echo "[apply-hooks/claude] would wire $event${matcher:+/$matcher} -> $cmd_expanded"
        continue
      fi

      if [[ -n "$matcher" ]]; then
        merged="$(jq --arg e "$event" --arg m "$matcher" --argjson h "$hookobj_expanded" '
          .hooks //= {} | .hooks[$e] //= [] |
          (.hooks[$e] | map(.matcher == $m) | index(true)) as $idx |
          if $idx == null then
            .hooks[$e] += [{matcher: $m, hooks: [$h]}]
          else
            .hooks[$e][$idx].hooks += [$h]
          end
        ' <<<"$merged")"
      else
        merged="$(jq --arg e "$event" --argjson h "$hookobj_expanded" '
          .hooks //= {} | .hooks[$e] //= [] |
          (.hooks[$e] | map(has("matcher") | not) | index(true)) as $idx |
          if $idx == null then
            .hooks[$e] += [{hooks: [$h]}]
          else
            .hooks[$e][$idx].hooks += [$h]
          end
        ' <<<"$merged")"
      fi
      echo "[apply-hooks/claude] wired $event${matcher:+/$matcher} -> $cmd_expanded"
    done
  done
done

if [[ $dry_run -eq 1 ]]; then
  exit 0
fi

if [[ "$(jq -S . <<<"$original")" == "$(jq -S . <<<"$merged")" ]]; then
  echo "[apply-hooks/claude] settings.json unchanged"
  exit 0
fi

if [[ -f "$settings" ]]; then mkdir -p "$backup_root"; cp -a "$settings" "$backup_root/claude-settings.json"; fi
mkdir -p "$(dirname "$settings")"
printf '%s\n' "$merged" | jq . >"$settings"
echo "[apply-hooks/claude] wired hooks into settings.json"
