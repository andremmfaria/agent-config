#!/usr/bin/env bash
# Layer: ux
# Stop + Notification desktop alert (port of oh-my-openagent's session /
# background notification hooks). Fires an OS notification when the agent
# finishes a turn (Stop) or needs attention (Notification). Best-effort across
# backends and always exits 0, so it can never block the agent.
# Arg $1 = hook event name (Stop | SubagentStop | Notification).
set -uo pipefail
event="${1:-Stop}"
payload="$(cat 2>/dev/null || true)"

case "$event" in
  Notification)
    title="Claude Code — attention needed"
    msg="$(printf '%s' "$payload" | jq -r '.message // "Claude needs your input."' 2>/dev/null)" ;;
  SubagentStop)
    title="Claude Code — subagent done"
    msg="A subagent finished its task." ;;
  *)
    title="Claude Code — done"
    msg="Agent finished this turn." ;;
esac

ts="$(date '+%F %T' 2>/dev/null || true)"
logfile="$HOME/.claude/notifications.log"
{ printf '%s\t%s\t%s\t%s\n' "$ts" "$event" "$title" "$msg" >>"$logfile"; } 2>/dev/null || true

if command -v notify-send >/dev/null 2>&1; then
  notify-send -a "Claude Code" "$title" "$msg" >/dev/null 2>&1 || true
elif command -v osascript >/dev/null 2>&1; then
  osascript -e "display notification \"${msg//\"/\'}\" with title \"$title\"" >/dev/null 2>&1 || true
fi
printf '\a' 2>/dev/null || true   # terminal-bell fallback
exit 0
