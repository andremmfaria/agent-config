#!/usr/bin/env bash
# PreToolUse / Bash guardrail.
# Reads the hook payload on stdin, inspects tool_input.command, and:
#   - DENY  catastrophic, irreversible system-level commands outright
#   - DENY  writes to protected config/secret paths (injection must not be
#           able to disable this gate or steal credentials)
#   - ASK   destructive-but-recoverable / commonly-sensitive commands
#   - allow everything else (stays silent -> normal Bash(*) behaviour)
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

# --- ASK: network / shell / privilege / package / VCS-publish side effects ----
# curl|wget piped straight into a shell interpreter (classic "curl | bash").
if printf '%s' "$cmd" | grep -Eq '\b(curl|wget)\b[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash|zsh)\b'; then
  emit ask "Pipes a remote download directly into a shell interpreter. Confirm the source before allowing."
fi
# sudo - privilege escalation.
if printf '%s' "$cmd" | grep -Eq '\bsudo\b'; then
  emit ask "sudo escalates privileges. Confirm before allowing."
fi
# Package/tool installers - mutate the environment, can run arbitrary postinstall code.
if printf '%s' "$cmd" | grep -Eq '\b(pip3?|npm|npx|pnpm|yarn|cargo|gem)\b[[:space:]]+install\b|\bgo[[:space:]]+install\b|\bbrew[[:space:]]+install\b|\bapt(-get)?[[:space:]]+install\b'; then
  emit ask "Installs a package - can run arbitrary code (postinstall/build scripts). Confirm before allowing."
fi
# crontab - persistent scheduled execution.
if printf '%s' "$cmd" | grep -Eq '\bcrontab\b'; then
  emit ask "crontab schedules persistent execution. Confirm before allowing."
fi
# systemctl unit lifecycle changes.
if printf '%s' "$cmd" | grep -Eq '\bsystemctl\b[[:space:]]+(enable|disable|start|stop|restart|mask)\b'; then
  emit ask "systemctl changes a service's running/boot state. Confirm before allowing."
fi
# chmod +x / chmod <mode with 7> - grants execute permission.
if printf '%s' "$cmd" | grep -Eq '\bchmod\b[[:space:]]+[^[:space:]]*\+x\b|\bchmod\b[[:space:]]+[0-7]*7[0-7]*([[:space:]]|$)'; then
  emit ask "chmod grants execute permission. Confirm before allowing."
fi
# git push to any remote (not just force).
if printf '%s' "$cmd" | grep -Eq '\bgit[[:space:]]+push\b'; then
  emit ask "git push publishes commits to a remote. Confirm before allowing."
fi
# gh pr/issue comment|create|merge|close - public/irreversible-ish GitHub actions.
if printf '%s' "$cmd" | grep -Eq '\bgh\b[[:space:]]+(pr|issue)[[:space:]]+(comment|create|merge|close)\b'; then
  emit ask "Creates/modifies a public GitHub PR or issue. Confirm before allowing."
fi
# gh release - publishes a release.
if printf '%s' "$cmd" | grep -Eq '\bgh\b[[:space:]]+release\b'; then
  emit ask "gh release publishes/modifies a GitHub release. Confirm before allowing."
fi
# curl/wget/http/httpie with an explicit write verb or a data/form/json payload
# flag - an outbound write from the shell to some host. The exfiltration DENY
# rule above already caught anything referencing a sensitive path, so by the
# time we get here this is a generic (non-sensitive) outbound write; still
# worth a confirmation since it has a side effect on a remote system.
if printf '%s' "$cmd" | grep -Eq '\b(curl|wget|http|httpie)\b' \
   && printf '%s' "$cmd" | grep -Eq -- '(-X[[:space:]]*(POST|PUT|PATCH|DELETE)\b|--data(-raw|-binary|-urlencode)?\b|-d\b|-F\b|--json\b)'; then
  emit ask "Sends an outbound write (POST/PUT/PATCH/DELETE or data/form/json payload) to a remote host. Confirm before allowing."
fi

# Default: allow (no output).
exit 0
