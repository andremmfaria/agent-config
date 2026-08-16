#!/usr/bin/env bash
# Layer: hard
# PreToolUse guard for outbound side-effect tools: SendMessage and MCP tools
# whose name implies posting/publishing outward (send/post/publish/email/
# slack/telegram/discord/tweet/comment/reply). Everything else is left alone.
#
# Rule: always ASK, naming the tool and previewing the outbound message, EXCEPT
# SendMessage targeting an in-process subagent — those are internal handoffs,
# not external sends. A target is treated as internal if it looks like a
# generated agent id (hex string, >=15 chars) or matches a known agent name
# from ~/.claude/agents/*.md.
#
# Output contract (PreToolUse): hookSpecificOutput.permissionDecision in
# {deny, ask, allow}. Emitting nothing = allow.
set -uo pipefail

payload="$(cat 2>/dev/null)" || exit 0
[ -z "$payload" ] && exit 0

tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
[ -z "$tool_name" ] && exit 0

# Only act on SendMessage or MCP tools whose name implies an outward send.
case "$tool_name" in
  SendMessage) ;;
  mcp__*)
    case "$tool_name" in
      *send*|*post*|*publish*|*email*|*slack*|*telegram*|*discord*|*tweet*|*comment*|*reply*) ;;
      *) exit 0 ;;
    esac
    ;;
  *) exit 0 ;;
esac

emit() { # $1 = decision (deny|ask), $2 = reason
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}' 2>/dev/null
  exit 0
}

# Exception: SendMessage to an in-process subagent (internal handoff, not an
# external send) — allow silently.
if [ "$tool_name" = "SendMessage" ]; then
  to="$(printf '%s' "$payload" | jq -r '.tool_input.to // empty' 2>/dev/null)"
  if [ -n "$to" ]; then
    # Generated agent ids: hex string, >=15 chars.
    if printf '%s' "$to" | grep -Eiq '^[a-f0-9]{15,}$'; then
      exit 0
    fi
    # Known agent name from ~/.claude/agents/*.md (basename without .md).
    agents_dir="$HOME/.claude/agents"
    if [ -d "$agents_dir" ]; then
      for f in "$agents_dir"/*.md; do
        [ -e "$f" ] || continue
        name="$(basename "$f" .md)"
        if [ "$name" = "$to" ]; then
          exit 0
        fi
      done
    fi
  fi
fi

preview="$(printf '%s' "$payload" | jq -r '(.tool_input.message // .tool_input.text // .tool_input.body // .tool_input.content // "") | tostring' 2>/dev/null)"
preview="${preview:0:100}"

emit ask "outbound-guard: $tool_name sends content outside this session. Preview: $preview"
