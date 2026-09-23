#!/usr/bin/env bash
# ibkr.sh - guarded wrapper around the ibkr CLI.
# Paper profile by default (set in ~/.config/ibkr-cli/config.toml), refuses order submission,
# refuses live profiles unless IBKR_ALLOW_LIVE=1, loads optional Flex credentials from pass,
# and routes `fx` to the forex helper.
set -uo pipefail

if ! command -v ibkr >/dev/null 2>&1; then
    echo "[ibkr] ibkr CLI not found. Install: uv tool install ibkr-cli --python 3.12" >&2
    exit 1
fi

for arg in "$@"; do
    case "$arg" in
        --submit)
            echo "[ibkr] refused: --submit is blocked by policy (paper, read-only phase). Order placement is a separate human decision." >&2
            exit 2 ;;
        gateway-live|live)
            if [ "${IBKR_ALLOW_LIVE:-0}" != "1" ]; then
                echo "[ibkr] refused: live profile '$arg' requires IBKR_ALLOW_LIVE=1 on the same command line." >&2
                exit 2
            fi ;;
    esac
done

# Forex (CASH on IDEALPRO) is not supported by ibkr-cli 0.7.2, which qualifies every symbol as a stock.
# `fx quote|bars PAIR` routes to the read-only ib_async helper using the CLI's own interpreter.
if [ "${1:-}" = "fx" ]; then
    shift
    SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    PY="$(dirname "$(readlink -f "$(command -v ibkr)")")/python"
    exec "$PY" "$SKILL_DIR/scripts/forex.py" "$@"
fi

source "$HOME/.claude/lib/skill-secrets.sh"
skill_secret IBKR_FLEX_TOKEN >/dev/null 2>&1 || true
skill_secret IBKR_FLEX_QUERY_ID >/dev/null 2>&1 || true

exec ibkr "$@"
