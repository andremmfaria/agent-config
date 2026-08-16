#!/usr/bin/env bash
# Layer: soft
# UserPromptSubmit nudge (port of oh-my-openagent's agent-usage-reminder).
# When a prompt looks like substantive work (build/debug/research/design/...),
# remind the orchestrator to DELEGATE to the right specialist and parallelize
# rather than doing deep work in the main loop. Stays silent on trivial prompts.
#
# Output contract (UserPromptSubmit): hookSpecificOutput.additionalContext is
# prepended to the model's context for this turn.
set -euo pipefail
payload="$(cat)"
prompt="$(printf '%s' "$payload" | jq -r '.prompt // empty')"
[ -z "$prompt" ] && exit 0

# Skip trivial / one-liner prompts.
[ "${#prompt}" -lt 24 ] && exit 0

# Trigger words implying delegable deep work.
if printf '%s' "$prompt" | grep -Eiq '\b(implement|build|creat(e|ing)|writ(e|ing)|refactor|debug|fix(es|ing)?|investigat|research|look(ing)? up|find out|design|architect|plan(ning)?|migrat|audit|review|optimi[sz]|analy[sz]|test(s|ing)?|benchmark|compar|scaffold|port(ing)?|integrat)\b'; then
  read -r -d '' ctx <<'EOF' || true
[Orchestration reminder] This looks like substantive work. Before doing it yourself, decide what to DELEGATE and to whom: craftsman (code / implementation / debugging), researcher (web research / verifying claims), thinker (architecture / tradeoffs), planner + preplanner + reviewer (requirements -> plan -> gate), writer (long-form prose / docs), scout + librarian (recon / docs lookup). Spawn independent subtasks IN PARALLEL via the Agent tool. Handle directly only if the task is trivial (<~2 min) or pure coordination of finished work.
EOF
  jq -n --arg c "$ctx" \
    '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
fi
exit 0
