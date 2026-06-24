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
    base_json='{"agents":{"defaults":{},"list":[]}}'
  fi

  # Read repo agents array as compact JSON for passing to jq
  local repo_agents
  repo_agents="$(jq -c '.agents' "$repo_openclaw")"

  # Build the merged openclaw JSON using jq:
  # For each repo agent, build a fragment {id, name, model:{primary:...}}
  # Upsert into .agents.list matched by .id:
  #   - if exists: existing * fragment  (recursive merge; live-only fields preserved)
  #   - if new:    fragment + {workspace: $HOME/.openclaw/agents/<id>/agent}
  # DO NOT override existing workspace on update.
  local merged
  merged="$(
    jq \
      --argjson repo_agents "$repo_agents" \
      --arg home "$HOME" \
      '
      # Build a lookup map: id -> existing live entry
      (.agents.list | map({key: .id, value: .}) | from_entries) as $live_map |

      # Build list of repo agent fragments
      ($repo_agents | map(
        {
          id:   .agent_id,
          name: .name,
          model: { primary: ("openai/" + .model) }
        }
      )) as $fragments |

      # Upsert: for each fragment, either merge into existing or create new
      ($fragments | map(
        . as $frag |
        if $live_map[.id] != null then
          # existing: merge live * fragment (live fields win for keys not in fragment,
          # fragment fields refresh id/name/model.primary only)
          ($live_map[.id] * $frag)
        else
          # new: fragment + computed workspace
          ($frag + {workspace: ($home + "/.openclaw/agents/" + .id + "/agent")})
        end
      )) as $upserted_by_repo |

      # Build set of repo agent ids for fast lookup
      ($fragments | map(.id) | unique) as $repo_ids |

      # Final list: preserve existing entries in their original order (updating if
      # in repo), then append new entries (those in repo but not yet in live)
      (.agents.list | map(
        . as $live_entry |
        # Find matching fragment (if any)
        ($fragments | map(select(.id == $live_entry.id)) | first) as $frag |
        if $frag != null then
          ($live_entry * $frag)
        else
          $live_entry
        end
      )) as $updated_existing |

      ($upserted_by_repo | map(select(.id as $id | ($live_map | has($id)) | not))) as $new_entries |

      # Reconstruct: all other top-level keys unchanged, only .agents.list replaced
      . + {
        agents: (.agents + {
          list: (($updated_existing + $new_entries) | map(del(.role)))
        })
      }
      ' <<< "$base_json"
  )"

  if [[ $dry_run -eq 1 ]]; then
    echo "# ===== apply-agents dry-run: openclaw ====="
    echo "$merged"
  else
    backup_file "$live_openclaw" "openclaw.json"
    echo "$merged" > "$live_openclaw"
    echo "[apply-agents/openclaw] wrote $live_openclaw"
  fi
}

apply_openclaw
