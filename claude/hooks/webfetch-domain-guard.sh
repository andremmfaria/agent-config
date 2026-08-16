#!/usr/bin/env bash
# Layer: hard
# PreToolUse guard for WebFetch / WebSearch / MCP fetch-like tools.
# Reads the target (WebFetch: tool_input.url, WebSearch: tool_input.query,
# MCP fetch tools: tool_input.url // tool_input.uri) and:
#   - DENY  the target embeds an obvious secret/credential (PEM key, cloud/API
#           tokens, long base64 blob, sensitive-path keywords) — outbound
#           requests must not be usable to exfiltrate local secrets via query
#           string or path.
#   - DENY  the target resolves to a private/loopback/link-local address or
#           localhost/.internal/.local — classic SSRF into the local network.
#   - ASK   the scheme isn't https (http, file://, ftp://, gopher://, ...).
#   - ASK   the host matches a glob in the configurable denylist file.
#   - allow everything else.
# Fails open (emits nothing) on any parse error or missing target, so a guard
# bug never wedges a session.
#
# Output contract (PreToolUse): hookSpecificOutput.permissionDecision in
# {deny, ask, allow}. Emitting nothing = allow.
set -uo pipefail

payload="$(cat 2>/dev/null)" || exit 0
[ -z "$payload" ] && exit 0

tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0

target=""
case "$tool_name" in
  WebFetch)
    target="$(printf '%s' "$payload" | jq -r '.tool_input.url // empty' 2>/dev/null)" ;;
  WebSearch)
    target="$(printf '%s' "$payload" | jq -r '.tool_input.query // empty' 2>/dev/null)" ;;
  *)
    # MCP fetch-like tools: try url, then uri.
    target="$(printf '%s' "$payload" | jq -r '.tool_input.url // .tool_input.uri // empty' 2>/dev/null)" ;;
esac
[ -z "${target:-}" ] && exit 0

emit() { # $1 = decision (deny|ask), $2 = reason
  jq -n --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $d, permissionDecisionReason: $r}}' 2>/dev/null
  exit 0
}

# --- DENY: credential / secret exfiltration in the URL or query ------------
if printf '%s' "$target" | grep -Fq -- '-----BEGIN'; then
  emit deny "webfetch-domain-guard: target embeds a PEM key marker (-----BEGIN). Likely exfiltration attempt."
fi
if printf '%s' "$target" | grep -Eq 'AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|xox[bap]-'; then
  emit deny "webfetch-domain-guard: target embeds what looks like a cloud/API/Slack token. Likely exfiltration attempt."
fi
if printf '%s' "$target" | grep -Eoq '[A-Za-z0-9+/=]{200,}'; then
  emit deny "webfetch-domain-guard: target embeds a long base64-like blob (>200 chars). Likely exfiltration attempt."
fi
if printf '%s' "$target" | grep -Eiq '\.ssh|id_rsa|\.env\b|secrets|credentials|token=|api_key=|password='; then
  emit deny "webfetch-domain-guard: target references a sensitive path/keyword (.ssh, id_rsa, .env, secrets, credentials, token=, api_key=, password=). Likely exfiltration attempt."
fi

# --- extract host (if target looks like a URL) ------------------------------
scheme=""
host=""
if printf '%s' "$target" | grep -Eq '^[a-zA-Z][a-zA-Z0-9+.-]*://'; then
  scheme="$(printf '%s' "$target" | sed -E 's#^([a-zA-Z][a-zA-Z0-9+.-]*)://.*#\1#')"
  authority="$(printf '%s' "$target" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://##' | sed -E 's#[/?#].*##')"
  authority="${authority##*@}"          # strip userinfo
  host="${authority%%:*}"               # strip port
  host="${host#\[}"; host="${host%\]}"  # strip IPv6 brackets
fi

# --- DENY: SSRF — private / loopback / link-local / internal targets -------
ssrf_re='(^|[^0-9])127\.|(^|[^0-9])10\.|(^|[^0-9])192\.168\.|(^|[^0-9])172\.(1[6-9]|2[0-9]|3[01])\.|(^|[^0-9])169\.254\.|localhost|\[::1\]|(^|\.)internal(\.|$|/)|(^|\.)local(\.|$|/)'
check_ssrf="${host:-$target}"
if printf '%s' "$check_ssrf" | grep -Eiq "$ssrf_re"; then
  emit deny "webfetch-domain-guard: target resolves to a private/loopback/link-local/internal host ($check_ssrf). SSRF risk."
fi

# --- ASK: non-https scheme --------------------------------------------------
if [ -n "$scheme" ]; then
  case "$scheme" in
    https) : ;;
    *) emit ask "webfetch-domain-guard: scheme '$scheme' is not https. Confirm before allowing." ;;
  esac
fi

# --- ASK: host on the configurable denylist ---------------------------------
if [ -n "$host" ]; then
  denylist="${CLAUDE_WEBFETCH_DENYLIST:-$HOME/.claude/webfetch-denylist.txt}"
  if [ -f "$denylist" ]; then
    while IFS= read -r pattern; do
      pattern="${pattern%%#*}"                      # strip trailing comments
      pattern="$(printf '%s' "$pattern" | xargs)"    # trim whitespace
      [ -z "$pattern" ] && continue
      # shellcheck disable=SC2254
      case "$host" in
        $pattern) emit ask "webfetch-domain-guard: host '$host' matches denylist entry '$pattern'. Confirm before allowing." ;;
      esac
    done <"$denylist"
  fi
fi

# Default: allow (no output).
exit 0
