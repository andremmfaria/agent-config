#!/usr/bin/env bash
# Layer: quality
# PostToolUse / Write|Edit nudge (ported from oh-my-openagent's comment-checker).
# Flags likely low-value / AI-filler comments (ones that restate the code) in the
# file just written. WARN-ONLY: it never edits files — it injects a note asking
# the agent to clean up. Threshold via COMMENT_CHECKER_THRESHOLD (default 3).
#
# To make it auto-strip instead, replace the jq nudge with an edit step — left
# out by design: a hook silently rewriting freshly-written files is surprising.
set -euo pipefail

threshold="${COMMENT_CHECKER_THRESHOLD:-3}"
payload="$(cat)"
file="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .tool_response.filePath // empty')"
[ -z "$file" ] && exit 0
[ -f "$file" ] || exit 0

# Source code only — skip docs/config/data where prose comments are expected.
case "$file" in
  *.md|*.markdown|*.txt|*.rst|*.adoc|*.json|*.yaml|*.yml|*.toml|*.ini|*.cfg|*.conf|*.lock|*.csv|*.tsv|*.svg|*.html|*.htm|*.xml) exit 0 ;;
esac

# Redundant / filler comment patterns following a // or # line-comment marker.
pat='(^|[[:space:]])(//|#)[[:space:]]*(increment|decrement|initialize|instantiate|create|construct|define|declare|returns?|returning|loop[[:space:]]*(through|over)?|iterate|assign|import|export|check[[:space:]]+if|now[[:space:]]+we|here[[:space:]]+we|we[[:space:]]+(need|will|now|can)|this[[:space:]]+(function|method|class|variable|loop|is|will)|set[[:space:]]+(the|up|a)|get[[:space:]]+the|add[[:space:]]+(a|the)|remove[[:space:]]+(a|the)|update[[:space:]]+the|store[[:space:]]+the|holds?[[:space:]]+the|call[[:space:]]+(the|a)|invoke|begin|end[[:space:]]+of|start[[:space:]]+of|temporary[[:space:]]+variable|placeholder|for[[:space:]]+loop|while[[:space:]]+loop|constructor|getter|setter)'

matches="$(grep -nEi "$pat" "$file" 2>/dev/null | head -20 || true)"
count="$(printf '%s' "$matches" | grep -c . || true)"
count="${count:-0}"
[ "$count" -lt "$threshold" ] && exit 0

sample="$(printf '%s\n' "$matches" | head -8)"
jq -n --arg f "$file" --arg n "$count" --arg s "$sample" '{
  systemMessage: ("comment-checker: " + $n + " possibly-redundant comments in " + ($f | gsub(".*/"; ""))),
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    additionalContext: ("comment-checker flagged " + $n + " likely low-value / AI-filler comments in " + $f + " — comments that restate WHAT the code does. Review and delete the redundant ones; keep only comments that explain WHY. Flagged lines:\n" + $s)
  }
}'
exit 0
