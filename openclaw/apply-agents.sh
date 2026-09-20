#!/usr/bin/env bash
set -euo pipefail

# openclaw/apply-agents.sh
# Idempotent upsert of repo agent definitions into ~/.openclaw/openclaw.json.
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
live_openclaw="$HOME/.openclaw/openclaw.json"
repo_openclaw="$repo_root/openclaw/openclaw.json"

backup_base="${AGENT_CONFIG_BACKUP_DIR:-$HOME/.agent-config-backups}"
timestamp="$(date +%Y%m%d-%H%M%S)"
backup_root="$backup_base/$timestamp"

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
    echo "# [apply-agents/openclaw] backup $src -> $backup_root/$label" >&2
    return
  fi

  local dst="$backup_root/$label"
  mkdir -p "$(dirname "$dst")"
  cp -a "$src" "$dst"
}

# ---------------------------------------------------------------------------
# OpenClaw merge
# ---------------------------------------------------------------------------
apply_openclaw() {
  local base_json

  if [[ -f "$live_openclaw" ]]; then
    base_json="$(cat "$live_openclaw")"
  else
    echo "# [apply-agents/openclaw] WARNING: $live_openclaw not found; using empty base" >&2
    base_json='{"agents":{"defaults":{},"entries":{}}}'
  fi

  # Read repo agents array as compact JSON for passing to jq
  local repo_agents
  repo_agents="$(jq -c '.agents' "$repo_openclaw")"

  # Read repo top-level tools policy (e.g. {"profile":"coding"}) for passing to jq
  local repo_tools_top
  repo_tools_top="$(jq -c '.tools // {}' "$repo_openclaw")"

  # Build the merged openclaw JSON using jq:
  # For each repo agent, build a fragment {name, model:{primary:...}, tools?}
  # (tools only included when the repo agent defines one, so agents without a
  # repo-side tools block never have their live tools policy clobbered).
  # Upsert into .agents.entries (an OBJECT keyed by agent id, since OpenClaw
  # 2026.9.1 replaced the legacy .agents.list array):
  #   - if key exists: existing * fragment  (recursive merge; live-only fields
  #     preserved, e.g. workspace, skills, thinkingDefault, models)
  #   - if key is new: fragment + {workspace: $HOME/.openclaw/agents/<id>/agent}
  # DO NOT override existing workspace on update.
  # .agents.defaults and .agents.ownership are left untouched.
  # Top-level .tools is deep-merged (repo overrides profile, live-only fields
  # like tools.web survive).
  local merged
  merged="$(
    jq \
      --argjson repo_agents "$repo_agents" \
      --argjson repo_tools_top "$repo_tools_top" \
      --arg home "$HOME" \
      '
      # Build a lookup object: id -> existing live entry
      ((.agents.entries // {})) as $live_entries |

      # Build id -> fragment map from the repo agent array
      ($repo_agents | map({
        key: .agent_id,
        value: (
          {
            name:  .name,
            model: { primary: ("openai/" + .model) }
          }
          + (if has("tools") then {tools: .tools} else {} end)
        )
      }) | from_entries) as $fragments |

      # Upsert: for each fragment id, merge into existing entry or create new
      ($fragments | to_entries | map(
        . as $f |
        if ($live_entries[$f.key] != null) then
          # existing: merge live * fragment (live fields win for keys not in
          # fragment; fragment refreshes name/model.primary/tools only)
          { key: $f.key, value: (($live_entries[$f.key] * $f.value) | del(.role)) }
        else
          # new: fragment + computed workspace
          { key: $f.key, value: ($f.value + {workspace: ($home + "/.openclaw/agents/" + $f.key + "/agent")}) }
        end
      ) | from_entries) as $upserted_by_repo |

      # Existing live entries: apply the upsert result where the id is in the
      # repo, otherwise leave the live-only entry (e.g. "main") untouched.
      ($live_entries | to_entries | map(
        .key as $k |
        if ($upserted_by_repo | has($k)) then
          { key: $k, value: $upserted_by_repo[$k] }
        else
          .
        end
      ) | from_entries) as $existing_merged |

      # New entries: in repo but not yet in live
      ($upserted_by_repo | to_entries | map(select(.key as $k | ($existing_merged | has($k)) | not)) | from_entries) as $new_entries |

      # Reconstruct: all other top-level keys unchanged, .tools deep-merged,
      # only .agents.entries replaced (.agents.defaults/.ownership preserved
      # via the base .agents spread)
      . + {
        tools: ((.tools // {}) * $repo_tools_top),
        agents: (.agents + {
          entries: ($existing_merged + $new_entries)
        })
      }
      ' <<< "$base_json"
  )"

  if [[ $dry_run -eq 1 ]]; then
    echo "# ===== apply-agents dry-run: openclaw ====="
    echo "$merged"
  else
    if [[ -f "$live_openclaw" ]] && printf '%s\n' "$merged" | cmp -s - "$live_openclaw"; then
      echo "[apply-agents/openclaw] unchanged $live_openclaw"
      return
    fi

    backup_file "$live_openclaw" "openclaw.json"
    printf '%s\n' "$merged" > "$live_openclaw"
    echo "[apply-agents/openclaw] wrote $live_openclaw"
  fi
}

apply_openclaw
