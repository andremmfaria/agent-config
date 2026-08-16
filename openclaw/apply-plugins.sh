#!/usr/bin/env bash
set -euo pipefail

# openclaw/apply-plugins.sh
# Installs/links openclaw/plugins/agent-config-guards into ~/.openclaw/plugins/
# via `openclaw plugins install --link` (style of openclaw/apply-approvals.sh:
# same --dry-run flag, same $HOME/.agent-config-backups backup convention).
# Then idempotently sets plugins.entries.agent-config-guards.enabled=true plus
# default config in ~/.openclaw/openclaw.json via jq (preserving every other
# key in that file — it also carries live provider API keys, so this script
# only ever touches the .plugins.entries["agent-config-guards"] subtree), and
# runs `openclaw config validate`.
# Script lives one level under repo root (repo/openclaw/), so repo_root is "..".
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plugin_dir="$repo_root/openclaw/plugins/agent-config-guards"
plugin_id="agent-config-guards"

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
live_config="$HOME/.openclaw/openclaw.json"

backup_base="${AGENT_CONFIG_BACKUP_DIR:-$HOME/.agent-config-backups}"
timestamp="$(date +%Y%m%d-%H%M%S)"
backup_root="$backup_base/$timestamp"

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  echo "[apply-plugins/openclaw] ERROR: jq is required" >&2
  exit 1
fi

if ! command -v openclaw >/dev/null 2>&1; then
  echo "[apply-plugins/openclaw] ERROR: openclaw CLI not found on PATH" >&2
  exit 1
fi

if [[ ! -d "$plugin_dir" ]]; then
  echo "[apply-plugins/openclaw] ERROR: plugin dir not found: $plugin_dir" >&2
  exit 1
fi

if [[ ! -f "$plugin_dir/openclaw.plugin.json" ]]; then
  echo "[apply-plugins/openclaw] ERROR: manifest not found: $plugin_dir/openclaw.plugin.json" >&2
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
    echo "# [apply-plugins/openclaw] backup $src -> $backup_root/$label" >&2
    return
  fi

  local dst="$backup_root/$label"
  mkdir -p "$(dirname "$dst")"
  cp -a "$src" "$dst"
}

# ---------------------------------------------------------------------------
# Step 1: install/link the plugin
# ---------------------------------------------------------------------------
install_plugin() {
  if [[ $dry_run -eq 1 ]]; then
    echo "# [apply-plugins/openclaw] dry-run: would run:"
    echo "#   openclaw plugins install --link '$plugin_dir'"
    echo "#   (falling back to 'openclaw plugins install --force \"$plugin_dir\"' if already linked from elsewhere)"
    return
  fi

  echo "[apply-plugins/openclaw] installing (linked) $plugin_dir"
  # --force is rejected together with --link ("linked plugins point at the
  # source path directly"), so try --link first (the idempotent path for a
  # dev-loop reinstall of the same source) and only fall back to a plain
  # --force install if that fails for some other reason (e.g. a prior
  # non-linked install of the same plugin id exists).
  if ! openclaw plugins install --link "$plugin_dir" 2>&1; then
    echo "[apply-plugins/openclaw] --link install failed; retrying with --force (non-linked)" >&2
    openclaw plugins install --force "$plugin_dir"
  fi
}

# ---------------------------------------------------------------------------
# Step 2: merge plugins.entries.agent-config-guards into openclaw.json
# ---------------------------------------------------------------------------
default_entry='{
  "enabled": true,
  "hooks": {
    "allowConversationAccess": true
  },
  "config": {
    "caveman": false,
    "notifyCommand": null,
    "webfetchDenylist": null,
    "protectedPaths": [],
    "workspaceOnlyWrites": true
  }
}'
# allowConversationAccess is required for the agent_end hook (session-
# notification's turn-finished handler): OpenClaw gates
# before_model_resolve/before_agent_reply/llm_input/llm_output/
# before_agent_finalize/agent_end/before_agent_run behind this per-plugin
# opt-in for any non-bundled plugin (docs/plugins/hooks.md). Verified live:
# without it, `openclaw plugins inspect --runtime --json` reports
# `typed hook "agent_end" blocked because non-bundled plugins must set
# plugins.entries.agent-config-guards.hooks.allowConversationAccess=true`
# in its `diagnostics` array, and the hook is silently absent from
# `typedHooks` (hookCount 12 instead of 13) — no error, no crash, just a
# quietly-missing handler. This plugin's agent_end handler only reads
# `event.success`/`event.error`/`event.durationMs` for a notification
# message; it does not read messages/prompt content.

apply_config() {
  local base_json

  if [[ -f "$live_config" ]]; then
    base_json="$(cat "$live_config")"
  else
    echo "[apply-plugins/openclaw] ERROR: $live_config not found; run \`openclaw\` once to generate it first" >&2
    exit 1
  fi

  # Force enabled=true; deep-merge default config UNDER any existing config so
  # user overrides win (jq's `*` is right-side-wins deep merge, so put
  # existing on the right of defaults). Idempotent: re-running with no config
  # drift produces byte-identical output.
  local merged
  merged="$(
    jq \
      --argjson default_entry "$default_entry" \
      --arg id "$plugin_id" \
      '
      .plugins //= {} |
      .plugins.entries //= {} |
      .plugins.entries[$id] = ($default_entry * (.plugins.entries[$id] // {})) |
      .plugins.entries[$id].enabled = true
      ' \
      <<< "$base_json"
  )"

  if [[ $dry_run -eq 1 ]]; then
    echo "# ===== apply-plugins dry-run: plugins.entries.$plugin_id ====="
    jq --arg id "$plugin_id" '.plugins.entries[$id]' <<< "$merged"
    return
  fi

  if printf '%s\n' "$merged" | cmp -s - "$live_config"; then
    echo "[apply-plugins/openclaw] unchanged $live_config"
    return
  fi

  backup_file "$live_config" "openclaw.json"
  printf '%s\n' "$merged" > "$live_config"
  echo "[apply-plugins/openclaw] wrote $live_config (plugins.entries.$plugin_id)"
}

install_plugin
apply_config

# ---------------------------------------------------------------------------
# Step 3: validate + show what registered (skip in dry-run: nothing changed)
# ---------------------------------------------------------------------------
if [[ $dry_run -eq 0 ]]; then
  echo
  echo "# ===== openclaw config validate ====="
  openclaw config validate

  echo
  echo "# ===== effective plugin entry (openclaw.json) ====="
  jq --arg id "$plugin_id" '.plugins.entries[$id]' "$live_config"

  echo
  echo "# ===== openclaw plugins list ====="
  openclaw plugins list || true
fi
