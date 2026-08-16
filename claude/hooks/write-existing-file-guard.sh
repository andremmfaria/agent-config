#!/usr/bin/env bash
# PreToolUse / Write guard (ported from oh-my-openagent's write-existing-file-guard).
# Denies a Write to a file that ALREADY EXISTS unless it was Read (or Edited)
# earlier in this session — preventing the "agent overwrites a file it never
# looked at" failure. New-file creates pass through untouched. Fail-open: if
# anything is unverifiable (no transcript, jq error) it ALLOWS, so a guard bug
# can never wedge a session.
#
# Output contract (PreToolUse): hookSpecificOutput.permissionDecision in
# {deny, ask, allow}. Emitting nothing = allow.
set -euo pipefail

payload="$(cat)"
file="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')"
[ -z "$file" ] && exit 0
# New file -> nothing to clobber -> allow.
[ -f "$file" ] || exit 0

transcript="$(printf '%s' "$payload" | jq -r '.transcript_path // empty')"
# Can't verify history -> fail open.
if [ -z "$transcript" ] || [ ! -f "$transcript" ]; then exit 0; fi

# Tool calls made inside subagents report the PARENT session's transcript_path,
# but their Read/Edit records land in <session-dir>/subagents/agent-*.jsonl —
# scan those too, or subagent Writes can never satisfy the guard.
scan=("$transcript")
subdir="${transcript%.jsonl}/subagents"
if [ -d "$subdir" ]; then
  for t in "$subdir"/agent-*.jsonl; do
    [ -f "$t" ] && scan+=("$t")
  done
fi

# Was this exact path Read / Edited / NotebookEdited earlier in the session?
# (Write is excluded so the in-flight call cannot self-satisfy the check.)
# Any jq error -> "true" -> fail open.
seen="$(jq -rs --arg f "$file" '
  [ .[]
    | (.message.content // [])
    | (if type=="array" then .[] else empty end)
    | select((.type? == "tool_use")
             and ((.name? == "Read") or (.name? == "Edit") or (.name? == "NotebookEdit")))
    | (.input.file_path // .input.notebook_path // empty)
  ] | any(. == $f)
' "${scan[@]}" 2>/dev/null || echo "true")"

[ "$seen" = "true" ] && exit 0

jq -n --arg f "$file" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: ("write-existing-file-guard: " + $f + " already exists but was not Read in this session. Read it first, then Write — this prevents clobbering content you have not seen. If a full regenerate is intended, Read it once to confirm scope, then retry the Write.")
  }
}'
exit 0
