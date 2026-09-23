#!/usr/bin/env bash
# check.sh - IBKR skill dependency and connectivity check (ibkr CLI against a local IB Gateway, paper by default)
set -uo pipefail

SKILL_OK=true
PROFILE="${IBKR_PROFILE:-gateway-paper}"

if command -v ibkr &>/dev/null; then
    echo "[ibkr] ibkr CLI: ok ($(command -v ibkr), version $(ibkr --version 2>/dev/null))"
else
    echo "[ibkr] WARN: ibkr CLI not found. Install: uv tool install ibkr-cli --python 3.12"
    SKILL_OK=false
fi

if command -v ibkr &>/dev/null; then
    DEF=$(ibkr config show 2>/dev/null | grep -i 'Default profile' | awk -F'│' '{print $3}' | xargs)
    if [ "$DEF" = "gateway-paper" ]; then
        echo "[ibkr] default profile: gateway-paper (127.0.0.1:4002)"
    else
        echo "[ibkr] WARN: default profile is '${DEF:-unset}', expected gateway-paper. Fix: ibkr config set default_profile gateway-paper"
        SKILL_OK=false
    fi
fi

source "$HOME/.claude/lib/skill-secrets.sh"
if skill_secret IBKR_FLEX_TOKEN >/dev/null 2>&1 && skill_secret IBKR_FLEX_QUERY_ID >/dev/null 2>&1; then
    echo "[ibkr] Flex credentials: present (optional)"
else
    echo "[ibkr] Flex credentials: absent (optional, only for trades/pnl/transfers reports)"
fi

if command -v ibkr &>/dev/null; then
    if ibkr doctor --profile "$PROFILE" 2>/dev/null | grep -qE 'reachable[^a-z]*yes'; then
        echo "[ibkr] Gateway TCP on profile $PROFILE: reachable"
        if ibkr doctor --api --profile "$PROFILE" >/dev/null 2>&1; then
            echo "[ibkr] Gateway API handshake: ok"
        else
            echo "[ibkr] WARN: Gateway reachable but API handshake failed (pending 2FA tap, API not enabled, trusted IP, or client id in use)"
            SKILL_OK=false
        fi
    else
        echo "[ibkr] WARN: no IB Gateway listening on profile $PROFILE. Start IB Gateway (paper login, port 4002, Read-Only API on) and approve 2FA on IBKR Mobile."
        SKILL_OK=false
    fi
fi

if $SKILL_OK; then
    echo "[ibkr] skill ready (paper, read-only)"
else
    echo "[ibkr] skill not ready"
    exit 1
fi
