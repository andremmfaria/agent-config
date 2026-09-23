#!/usr/bin/env bash
# check.sh - alpaca skill dependency and connectivity check (official alpaca CLI, paper account, read-only)
set -uo pipefail

SKILL_OK=true
BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="$BASE_DIR/scripts/alpaca.sh"

if command -v alpaca &>/dev/null; then
    echo "[alpaca] alpaca CLI: ok ($(command -v alpaca), version $(alpaca version 2>/dev/null))"
else
    echo "[alpaca] WARN: alpaca CLI not found. Install: download cli_<version>_linux_amd64.tar.gz from https://github.com/alpacahq/cli/releases and extract the alpaca binary into ~/.local/bin"
    SKILL_OK=false
fi

source "$HOME/.claude/lib/skill-secrets.sh"
if skill_secret ALPACA_API_KEY >/dev/null 2>&1 && skill_secret ALPACA_API_SECRET >/dev/null 2>&1; then
    echo "[alpaca] secrets: present (ALPACA_API_KEY, ALPACA_API_SECRET)"
else
    echo "[alpaca] WARN: secrets missing. Add with: pass insert openclaw/ALPACA_API_KEY, pass insert openclaw/ALPACA_API_SECRET"
    SKILL_OK=false
fi

if command -v alpaca &>/dev/null; then
    if bash "$WRAPPER" doctor 2>/dev/null | grep -q 'All checks passed.'; then
        echo "[alpaca] doctor: ok (paper, connected)"
    else
        echo "[alpaca] WARN: doctor did not report all checks passed. Run: bash $WRAPPER doctor"
        SKILL_OK=false
    fi

    START="$(date -d '10 days ago' +%F 2>/dev/null || date -v-10d +%F 2>/dev/null)"
    if bash "$WRAPPER" data bars --symbol AAPL --timeframe 1Day --start "$START" --feed sip 2>/dev/null | grep -q '"bars"'; then
        echo "[alpaca] data call: ok (AAPL daily bars since $START)"
    else
        echo "[alpaca] WARN: data call failed. Run: bash $WRAPPER data bars --symbol AAPL --timeframe 1Day --start $START --feed sip"
        SKILL_OK=false
    fi
fi

if $SKILL_OK; then
    echo "[alpaca] skill ready (paper, read-only)"
else
    echo "[alpaca] skill not ready"
    exit 1
fi
