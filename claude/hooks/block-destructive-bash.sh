#!/usr/bin/env bash
# PreToolUse / Bash guardrail.
# Reads the hook payload on stdin, inspects tool_input.command, and:
#   - DENY  catastrophic, irreversible system-level commands outright
#   - DENY  writes to protected config/secret paths (injection must not be
#           able to disable this gate or steal credentials)
#   - DENY  credential/secret exfiltration attempts
#   - ASK   only commands that are really destructive but recoverable (rm -r/-f,
#           find -delete/-exec rm, git reset --hard / clean / checkout-discard /
#           restore, truncate/shred, curl|wget piped into a shell, git push
#           --force). Everything else (sudo, package installs, chmod +x,
#           crontab, systemctl, plain git push, gh writes, HTTP write verbs,
#           ...) is an ordinary apply operation and runs silently.
#   - allow everything else (stays silent -> normal Bash(*) behaviour)
#
# Policy: ask only on really destructive commands; deny only on catastrophic /
# exfiltration / gate-tampering commands. Ordinary apply operations (writes,
# commits, pushes, installs, sudo, chmod, gh) are silent by design.
#
# Output contract (PreToolUse): hookSpecificOutput.permissionDecision in
# {deny, ask, allow} with a permissionDecisionReason. Emitting nothing = allow.
set -euo pipefail

payload="$(cat)"
cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty')"

# Nothing to inspect -> allow silently.
[ -z "$cmd" ] && exit 0

emit() { # $1 = decision (deny|ask), $2 = reason
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}'
  exit 0
}

# --- shared path fragments -----------------------------------------------
# Home reference forms: literal ~, $HOME, or /home/<user>.
HOME_RE='(~|\$HOME|/home/[A-Za-z0-9_.-]+)'
# Directory trees where ANY write underneath is protected.
PROT_DIR_RE="${HOME_RE}/(\\.ssh|\\.gnupg|\\.claude/hooks|\\.openclaw/hooks)"
# Individual protected files (config/secrets/gate itself/shell rc files).
PROT_FILE_RE="${HOME_RE}/(\\.claude/settings\\.json|\\.claude/settings\\.local\\.json|\\.openclaw/openclaw\\.json|\\.openclaw/exec-approvals\\.json|\\.bashrc|\\.profile|\\.zshrc)"
# Repo-local git hooks dir (no home prefix - relative to any repo).
GIT_HOOKS_RE='(^|[^[:alnum:]_])\.git/hooks/'
PROTECTED_RE="(${PROT_DIR_RE}|${PROT_FILE_RE}|${GIT_HOOKS_RE})"
# Sensitive-data path/keyword fragments for the exfil rules below.
SENSITIVE_RE='(~/\.ssh|/etc/passwd|/etc/shadow|\.env\b|secrets|credentials|token|id_rsa|\.claude|\.openclaw|\.aws|\.gnupg)'

# --- HARD DENY: catastrophic / irreversible -----------------------------------
# rm -rf targeting root, home, or wildcard-of-root; recursive-force on / or ~.
if printf '%s' "$cmd" | grep -Eq '\brm[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*[fF]|-[a-zA-Z]*[fF][a-zA-Z]*[rR]|-[rRfF][[:space:]]+-[rRfF])[a-zA-Z]*([[:space:]]+--)?[[:space:]]+(/|~|\$HOME|/\*|~/\*|\.\.?)([[:space:]]|$)'; then
  emit deny "Blocked: recursive force-delete of a root/home/parent path. If truly intended, run it manually in a terminal."
fi
# Disk-destroyers and fork bomb.
if printf '%s' "$cmd" | grep -Eq '\bmkfs(\.[a-z0-9]+)?\b|\bdd\b[^|]*\bof=/dev/|>[[:space:]]*/dev/(sd|nvme|hd|vd)|:\(\)\s*\{\s*:\|:&\s*\};:'; then
  emit deny "Blocked: disk-format / raw-device write / fork bomb. Catastrophic and irreversible."
fi
# chmod/chown -R on root.
if printf '%s' "$cmd" | grep -Eq '\bch(mod|own)[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+)[^[:space:]]+[[:space:]]+/([[:space:]]|$)'; then
  emit deny "Blocked: recursive permission/ownership change on / . Catastrophic."
fi

# --- HARD DENY: writes to protected config/secret paths -----------------------
# Redirect (>, >>) into a protected path.
if printf '%s' "$cmd" | grep -Eq "(>|>>)[[:space:]]*['\"]?${PROTECTED_RE}"; then
  emit deny "Blocked: redirect writes into a protected path (SSH/GPG keys, hook scripts, settings, shell rc, or .git/hooks). Injection must not be able to disable the safety gate or tamper with keys."
fi
# tee into a protected path.
if printf '%s' "$cmd" | grep -Eq "\btee\b[^|]*${PROTECTED_RE}"; then
  emit deny "Blocked: tee writes into a protected path (SSH/GPG keys, hook scripts, settings, shell rc, or .git/hooks). Injection must not be able to disable the safety gate or tamper with keys."
fi
# cp / mv / install touching a protected path (source or destination).
if printf '%s' "$cmd" | grep -Eq "\b(cp|mv|install)\b[^|]*${PROTECTED_RE}"; then
  emit deny "Blocked: cp/mv/install touches a protected path (SSH/GPG keys, hook scripts, settings, shell rc, or .git/hooks). Injection must not be able to disable the safety gate or exfiltrate keys."
fi
# sed -i in-place edit of a protected path.
if printf '%s' "$cmd" | grep -Eq "\bsed\b[^|]*-i[^|]*${PROTECTED_RE}"; then
  emit deny "Blocked: sed -i edits a protected path (SSH/GPG keys, hook scripts, settings, shell rc, or .git/hooks). Injection must not be able to disable the safety gate."
fi

# --- HARD DENY: credential/secret exfiltration ---------------------------------
# curl/wget/nc/ncat/socat sending data (-d/--data/-F/-T/--upload-file/@file) that
# references a sensitive path (ssh keys, env files, secrets, tokens, cloud creds).
if printf '%s' "$cmd" | grep -Eq '\b(curl|wget|nc|ncat|socat)\b' \
   && printf '%s' "$cmd" | grep -Eq -- '(-d|--data(-binary)?|-F|-T|--upload-file|@)' \
   && printf '%s' "$cmd" | grep -Eq "$SENSITIVE_RE"; then
  emit deny "Blocked: outbound request appears to upload/reference a sensitive path (SSH keys, .env, secrets, tokens, cloud credentials). Likely exfiltration attempt."
fi
# base64/xxd-encoding a sensitive path and piping it to a network tool.
if printf '%s' "$cmd" | grep -Eq "\b(base64|xxd)\b[^|]*${SENSITIVE_RE}[^|]*\|[^|]*\b(curl|wget|nc|ncat|socat)\b"; then
  emit deny "Blocked: encodes a sensitive path and pipes it to a network tool. Likely exfiltration attempt."
fi

# --- ASK: destructive but recoverable / commonly intentional ------------------
if printf '%s' "$cmd" | grep -Eq '\brm[[:space:]]+(-[a-zA-Z]*[rR]|-[a-zA-Z]*[fF])'; then
  emit ask "rm with -r/-f deletes without recovery. Confirm the target before allowing."
fi
if printf '%s' "$cmd" | grep -Eq '\bfind\b.*-delete\b|\bfind\b.*-exec(dir)?[[:space:]]+rm\b'; then
  emit ask "find with -delete or -exec/-execdir rm deletes matched files. Confirm before allowing."
fi
if printf '%s' "$cmd" | grep -Eq '\bgit[[:space:]]+reset[[:space:]]+(--hard|--keep[[:space:]].*|.*--hard)'; then
  emit ask "git reset --hard discards uncommitted work. Confirm before allowing."
fi
if printf '%s' "$cmd" | grep -Eq '\bgit[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[fdx]'; then
  emit ask "git clean -f/-d/-x deletes untracked files irreversibly. Confirm before allowing."
fi
if printf '%s' "$cmd" | grep -Eq '\bgit[[:space:]]+(checkout[[:space:]]+--[[:space:]]|restore[[:space:]])'; then
  emit ask "checkout-discard / restore can overwrite local changes. Confirm before allowing."
fi
if printf '%s' "$cmd" | grep -Eq '\b(truncate|shred)\b'; then
  emit ask "truncate/shred destroys file contents. Confirm before allowing."
fi

# --- ASK: remaining really-destructive commands --------------------------------
# curl|wget piped straight into a shell interpreter (classic "curl | bash").
# Deliberately kept even though it is a common install pattern: it runs
# arbitrary, unreviewed remote code.
if printf '%s' "$cmd" | grep -Eq '\b(curl|wget)\b[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash|zsh)\b'; then
  emit ask "Pipes a remote download directly into a shell interpreter. Confirm the source before allowing."
fi
# git push --force / --force-with-lease / -f - overwrites remote history.
# Plain (non-force) git push is an ordinary apply operation and runs silently.
if printf '%s' "$cmd" | grep -Eq '\bgit[[:space:]]+push\b.*(--force(-with-lease(=[^[:space:]]+)?)?|[[:space:]]-f([[:space:]]|$))'; then
  emit ask "git push --force/-f overwrites remote history. Confirm before allowing."
fi

# Default: allow (no output).
exit 0
