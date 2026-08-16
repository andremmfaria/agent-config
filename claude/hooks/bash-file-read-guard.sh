#!/usr/bin/env bash
# Layer: style
# PreToolUse / Bash nudge (ported from oh-my-openagent's bash-file-read-guard).
# When the agent uses cat/head/tail to read a SINGLE file, nudge it toward the
# Read tool (line numbers, hash anchors, Edit integration). Non-blocking: emits
# no permissionDecision, so the command still runs and other guards still apply.
set -euo pipefail

payload="$(cat)"
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')"
[ -z "$cmd" ] && exit 0

# Skip pipelines, redirects, substitutions, multi-command lines, xargs — those
# are legitimate "transform/stream" uses, not "just read a file".
case "$cmd" in
  *'|'*|*'>'*|*'<'*|*'$('*|*'`'*|*'&&'*|*';'*|*xargs*) exit 0 ;;
esac
# tail -f / follow = legit streaming (logs).
printf '%s' "$cmd" | grep -Eq '\btail\b[^|]*-[a-zA-Z]*f' && exit 0

set -f  # no glob expansion while we tokenize
# Drop a leading sudo, then split into tool + rest.
c="${cmd#"${cmd%%[![:space:]]*}"}"          # ltrim
c="${c#sudo }"
tool="${c%%[[:space:]]*}"
rest="${c#"$tool"}"
case "$tool" in cat|head|tail) ;; *) exit 0 ;; esac

# Count non-flag, non-number args (the actual file paths).
nargs=0; file=""
for tok in $rest; do
  case "$tok" in
    -*) ;;          # flag
    [0-9]*) ;;      # numeric flag value, e.g. head -n 20
    *) nargs=$((nargs+1)); file="$tok" ;;
  esac
done
set +f

[ "$nargs" -ne 1 ] && exit 0
case "$file" in *'*'*|*'?'*|'') exit 0 ;; esac   # globs / empty -> skip

jq -n --arg f "$file" --arg t "$tool" '{
  systemMessage: ("Hint: " + $t + " " + $f + " — prefer the Read tool."),
  suppressOutput: true,
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    additionalContext: ("You used `" + $t + " " + $f + "` via Bash to read a single file. Prefer the Read tool for file contents: it returns line numbers + hash anchors and integrates with Edit. Reserve cat/head/tail for piping or transforming output.")
  }
}'
exit 0
