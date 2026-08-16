#!/usr/bin/env bash
# PreToolUse / Write|Edit|MultiEdit|NotebookEdit path guard.
# Reads tool_input.file_path (Write/Edit/MultiEdit) or tool_input.notebook_path
# (NotebookEdit), resolves it (expand ~/$HOME, normalize, follow symlinks), and:
#   - DENY a target inside a protected path (same set block-destructive-bash.sh
#     protects from Bash writes - injection must not disable the gate this way
#     either).
#   - ASK  a target outside both the session cwd and a /tmp/claude-* scratchpad
#     dir, but ONLY if the target file already exists. Overwriting an existing
#     file far outside the working tree is the destructive case; creating a
#     brand-new file out there is not (it can't clobber anything), so that
#     case runs silently.
#   - allow otherwise.
# Fails open (emits nothing) on any parse error, so a guard bug never wedges
# a session.
#
# Output contract (PreToolUse): hookSpecificOutput.permissionDecision in
# {deny, ask, allow}. Emitting nothing = allow.
set -uo pipefail

payload="$(cat 2>/dev/null)" || exit 0
[ -z "$payload" ] && exit 0

file="$(printf '%s' "$payload" | jq -r '(.tool_input.file_path // .tool_input.notebook_path // empty)' 2>/dev/null)"
[ -z "${file:-}" ] && exit 0

emit() { # $1 = decision (deny|ask), $2 = reason
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
  exit 0
}

# Expand ~ and literal $HOME forms, then normalize. realpath -m works on
# non-existent paths (lexical normalization) and resolves symlinks along any
# existing prefix, so an existing symlink pointing INTO a protected dir also
# resolves to its real (protected) target.
resolve_path() {
  local p="$1"
  case "$p" in
    "~"*) p="${HOME}${p#\~}" ;;
  esac
  p="${p//\$HOME/$HOME}"
  if command -v realpath >/dev/null 2>&1; then
    realpath -m -- "$p" 2>/dev/null || printf '%s' "$p"
  else
    printf '%s' "$p"
  fi
}

resolved="$(resolve_path "$file")"
[ -z "$resolved" ] && exit 0

# Same protected set as block-destructive-bash.sh, expressed against a
# resolved absolute path instead of raw command text.
protected_re="^${HOME}/(\\.ssh|\\.gnupg|\\.claude/hooks|\\.openclaw/hooks)(/|\$)"
protected_re="${protected_re}|^${HOME}/\\.claude/settings\\.json\$"
protected_re="${protected_re}|^${HOME}/\\.claude/settings\\.local\\.json\$"
protected_re="${protected_re}|^${HOME}/\\.openclaw/(openclaw|exec-approvals)\\.json\$"
protected_re="${protected_re}|^${HOME}/\\.(bashrc|profile|zshrc)\$"
protected_re="${protected_re}|(^|/)\\.git/hooks/"

if printf '%s' "$resolved" | grep -Eq "$protected_re"; then
  emit deny "write-path-guard: $resolved is a protected path (SSH/GPG keys, hook scripts, settings, shell rc, or .git/hooks). Injection must not be able to disable the safety gate or tamper with keys."
fi

# Determine the working root: payload .cwd if present, else this process's $PWD.
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"
[ -z "$cwd" ] && cwd="$PWD"
cwd_resolved="$(resolve_path "$cwd")"

in_scope=0
case "$resolved" in
  "$cwd_resolved"|"$cwd_resolved"/*) in_scope=1 ;;
  /tmp/claude-*) in_scope=1 ;;
esac

if [ "$in_scope" -eq 0 ] && [ -e "$resolved" ]; then
  emit ask "write-path-guard: $resolved is outside the working directory ($cwd_resolved) and outside any /tmp/claude-* scratchpad, and the file already exists. Confirm before overwriting it."
fi

# Default: allow (no output).
exit 0
