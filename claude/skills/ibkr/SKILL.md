---
name: ibkr
description: "Interactive Brokers account access via the ibkr CLI (fatwang2/ibkr-cli on ib_async) against a local IB Gateway. Account summary, positions, orders, quotes, historical bars (forex CASH and US stocks), news, Flex reports. Paper profile on port 4002 by default, read-only by policy. Use when the user mentions IBKR, Interactive Brokers, IB Gateway, TWS, positions, paper account, EUR/USD bars, or the trading bot's broker."
---

# IBKR Skill

Run `bash {baseDir}/check.sh` to verify the CLI, config, and Gateway connectivity before first use.

## What talks to what

- `ibkr` (uv tool, `~/.local/bin/ibkr`, ib_async) connects only to a local IB Gateway or TWS socket. It holds no IBKR login. The login lives in the Gateway process, which the user starts and approves with IBKR Mobile two-factor.
- Profiles: `gateway-paper` 127.0.0.1:4002 (default), `gateway-live` 127.0.0.1:4001, `paper` 7497, `live` 7496. Config at `~/.config/ibkr-cli/config.toml`.
- Policy for the ai-trading-bot project: paper only, Gateway Read-Only API on, no order submission. The wrapper below enforces the first and last; the Gateway setting is the user's.

## Always call through the wrapper

```bash
bash {baseDir}/scripts/ibkr.sh <command> [args]
```

The wrapper refuses `--submit`, refuses live profiles unless `IBKR_ALLOW_LIVE=1` is set in the same command, and loads the optional Flex credentials from `pass`. Never pass `--submit` yourself. Order placement is a separate, explicit user decision that also requires the Gateway's Read-Only API to be turned off by the user.

## Common calls

All examples: `IB="bash {baseDir}/scripts/ibkr.sh"`.

```bash
# Connectivity
$IB doctor              # config + TCP reachability
$IB doctor --api        # full API handshake, non-zero exit on failure

# Account
$IB account summary --json
$IB positions --json

# Orders (read)
$IB orders open --json
$IB orders completed --json
$IB orders executions --json

# Quotes and bars
$IB quote AAPL --json
$IB fx --json quote EUR.USD                              # forex, CASH on IDEALPRO, via the forex helper
$IB fx --json bars EURUSD --duration "30 D" --bar-size "1 hour" --what-to-show MIDPOINT
$IB bars AAPL --duration "1 D" --bar-size "5 mins" --json

# News (free providers on API: BRFG, BRFUPDN, DJNL)
$IB news providers
$IB news headlines AAPL --limit 20 --providers "BRFG,DJNL" --json

# Preview an order without sending it (what-if, allowed)
$IB buy AAPL 1 --preview
```

## Gotchas

- Env vars do not persist between Bash calls, so `IBKR_ALLOW_LIVE=1` must be on the same command line as the call it unlocks.
- ibkr-cli 0.7.2 qualifies every symbol as a stock, so `quote EURUSD` and `bars EURUSD` fail with "No security definition". Forex goes through `fx quote|bars`, a read-only ib_async helper in `scripts/forex.py` that connects with the same client id, read-only flag on. Pairs accept EURUSD, EUR.USD or EUR/USD. Bars default to MIDPOINT (volume is always -1 for forex).
- With no market data subscription, paper stock quotes fall back to delayed data. Forex IDEALPRO quotes are free and live.
- Client ID defaults to 1 per profile. If another process (NautilusTrader, a logger) already uses client id 1 on the same Gateway, the handshake fails; edit the profile's `client_id` in the config file.
- The Gateway restarts daily and needs a fresh two-factor tap after the weekly reset around 01:00 ET Sunday. A TCP-ok but API-failing doctor usually means the Gateway is waiting on that tap.
- `ibkr update` checks PyPI. Upgrade with `uv tool upgrade ibkr-cli` instead.
- Flex Queries (`trades`, `pnl`, transfers, dividends) need `IBKR_FLEX_TOKEN` and `IBKR_FLEX_QUERY_ID` in `pass` under `openclaw/`. They go to IBKR's Flex web service over HTTPS, not the Gateway. Optional.

## Credentials

- None for the CLI itself.
- IBKR username, password and two-factor stay in the Gateway (or its Docker container env), never in this skill, never in chat.
- Optional: `pass insert openclaw/IBKR_FLEX_TOKEN` and `pass insert openclaw/IBKR_FLEX_QUERY_ID` for Flex reports. The user inserts them; see the credential-storage skill.

## Gateway

IB Gateway runs as a Docker container from `ghcr.io/gnzsnz/ib-gateway:stable` (IB Gateway 10.45.1j with IBC), paper mode, Read-Only API on, API bound to 127.0.0.1:4002 only. Compose project: `~/ib-gateway/` (docker-compose.yml, an env file with the paper login, tws_settings/ volume). Nothing in that directory belongs in any repo.

```bash
GW="docker compose -f $HOME/ib-gateway/docker-compose.yml"

$GW up -d                     # start (paper login needs no tap; a live login needs an IBKR Mobile tap at start and after the Sunday reset)
$GW logs -f --tail 100        # watch the login; "Second Factor Authentication" lines = waiting for the tap
$GW ps                        # container state
$GW restart                   # re-auth: restart the container, then approve the new tap on IBKR Mobile
$GW down                      # stop
docker exec ib-gateway-paper ss -ltn   # 4002 (API) and 4004 (socat) listening inside the container
```

- Daily restart is `AUTO_RESTART_TIME` in the compose file (03:00 AM Europe/Dublin). That restart keeps the session, only the weekly IBKR reset (around 01:00 ET Sunday) needs a fresh login, which IBC performs on its own.
- Observed 2026-09-23: the paper username logged in with password only, no second-factor prompt at all, so the Gateway is fully unattended today. A live username would trigger IBKR Mobile.
- One username holds one session. `TRADING_MODE=both` with the same username in both slots makes the second Gateway collide ("Existing session detected") and shut down. Dual mode needs the dedicated live username in `TWS_USERID` and the paper username in `TWS_USERID_PAPER`, plus port `127.0.0.1:4001:4003`.
- A missed tap: `TWOFA_TIMEOUT_ACTION=restart` plus `RELOGIN_AFTER_TWOFA_TIMEOUT=yes` makes the Gateway re-prompt on its own. Watch the logs and tap again.
- VNC fallback for a stuck login dialog: `127.0.0.1:5900`, password is `VNC_SERVER_PASSWORD` from the env file in `~/ib-gateway/`. No VNC client is installed on the host; tunnel port 5900 to a machine that has one, or install `tigervnc-viewer`.
- Credential keys in the env file at `~/ib-gateway/`: `TWS_USERID`, `TWS_PASSWORD` (paper login), `VNC_SERVER_PASSWORD`. The user edits that file, mode 600. Never read it back into chat.
- Read-Only API is enforced by the container (`READ_ONLY_API=yes` in the compose file), independently of the wrapper's `--submit` refusal.
- After the container is up, run `bash {baseDir}/check.sh`. Expected last line: `[ibkr] skill ready (paper, read-only)`.
