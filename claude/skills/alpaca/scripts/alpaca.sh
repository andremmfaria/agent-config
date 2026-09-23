#!/usr/bin/env bash
# alpaca.sh - guarded wrapper around the alpaca CLI.
# Paper account by default (env-var credentials, no profile file), read-only whitelist,
# refuses live trading and any command that submits, cancels, transfers, or mutates state.
set -uo pipefail

if ! command -v alpaca >/dev/null 2>&1; then
    echo "[alpaca] alpaca CLI not found. Install: download cli_<version>_linux_amd64.tar.gz from https://github.com/alpacahq/cli/releases and extract the alpaca binary into ~/.local/bin" >&2
    exit 1
fi

refuse() {
    echo "[alpaca] refused: $1" >&2
    exit 2
}

for arg in "$@"; do
    [ "$arg" = "--live" ] && refuse "--live is blocked by policy (paper account only)"
done

# --profile/-p may be given as "--profile NAME" or "--profile=NAME" (long form only; this CLI has no
# documented short-flag-attached form for -p, so that variant is not handled here).
prev=""
for arg in "$@"; do
    case "$arg" in
        --profile=*) val="${arg#--profile=}"; [ "$val" = "paper" ] || refuse "profile '$val' is blocked by policy (paper only)" ;;
        -p=*) val="${arg#-p=}"; [ "$val" = "paper" ] || refuse "profile '$val' is blocked by policy (paper only)" ;;
    esac
    if [ "$prev" = "--profile" ] || [ "$prev" = "-p" ]; then
        [ "$arg" = "paper" ] || refuse "profile '$arg' is blocked by policy (paper only)"
    fi
    prev="$arg"
done

# Find the top two positional (non-flag) words: value-taking global flags (--profile/-p, --jq,
# --timeout) have their value skipped so it is never mistaken for a subcommand.
cmd=""
sub=""
skip_next=0
for arg in "$@"; do
    if [ "$skip_next" = 1 ]; then
        skip_next=0
        continue
    fi
    case "$arg" in
        --profile|-p|--jq|--timeout) skip_next=1; continue ;;
        -*) continue ;;
        *)
            if [ -z "$cmd" ]; then
                cmd="$arg"
            elif [ -z "$sub" ]; then
                sub="$arg"
            fi
            ;;
    esac
done

case "$cmd" in
    ""|account|data|calendar|clock|asset|corporate-action|doctor|version)
        # account config set is the one write buried under an otherwise read-only tree
        if [ "$cmd" = "account" ] && [ "$sub" = "config" ]; then
            for arg in "$@"; do
                [ "$arg" = "set" ] && refuse "'account config set' mutates account configuration, blocked by policy"
            done
        fi
        ;;
    position)
        case "$sub" in
            list|get|"") ;;
            *) refuse "'position $sub' is blocked by policy (read-only: list, get)" ;;
        esac
        ;;
    order)
        case "$sub" in
            list|get|get-by-client-id|"") ;;
            *) refuse "'order $sub' is blocked by policy (read-only: list, get, get-by-client-id)" ;;
        esac
        ;;
    watchlist)
        case "$sub" in
            list|get|get-by-name|"") ;;
            *) refuse "'watchlist $sub' is blocked by policy (read-only: list, get, get-by-name)" ;;
        esac
        ;;
    profile)
        case "$sub" in
            list|"") ;;
            *) refuse "'profile $sub' is blocked by policy (read-only: list)" ;;
        esac
        ;;
    api)
        # method is the first token after "api": GET, or a path (implicit GET), never POST/PUT/PATCH/DELETE
        case "$sub" in
            ""|GET|/*) ;;
            *) refuse "'api $sub' is blocked by policy (GET only)" ;;
        esac
        ;;
    option|locate|wallet)
        refuse "'$cmd' is blocked by policy (trading/transfer surface, not in the read-only whitelist)"
        ;;
    update)
        refuse "'update' is blocked by policy; upgrade manually from https://github.com/alpacahq/cli/releases"
        ;;
    *)
        refuse "'$cmd' is not in the read-only whitelist"
        ;;
esac

source "$HOME/.claude/lib/skill-secrets.sh"
skill_require ALPACA_API_KEY ALPACA_API_SECRET
export ALPACA_SECRET_KEY="$ALPACA_API_SECRET"

exec alpaca "$@"
