---
name: alpaca
description: "Alpaca Markets paper account and free market data via the official alpaca CLI: account, positions, orders (read), stock bars, quotes, trades, news, calendar, clock, assets, corporate actions. Read-only by policy, paper keys only, data source for the trading bot (IBKR is the broker). Use when the user mentions Alpaca, US stock bars, SIP history, or the bot's data source."
---

# Alpaca Skill

Run `bash {baseDir}/check.sh` to verify the CLI, credentials, and connectivity before first use.

## What talks to what

- `alpaca` (official Go CLI, `github.com/alpacahq/cli`, `~/.local/bin/alpaca`) talks to two Alpaca hosts: `paper-api.alpaca.markets` for account, positions, orders and `data.alpaca.markets` for market data. Both are reached with the same API key pair.
- The keys in this skill are paper trading keys on the Basic (free) market data plan.
- Basic plan limits: SIP historical bars, quotes and trades go back to 2016, but the newest 15 minutes of history is withheld. Real-time streaming and snapshots are IEX only, not SIP. Rate limit is 200 requests per minute.
- The ai-trading-bot project never trades at Alpaca. IBKR is the broker. Alpaca is a data source and a paper sandbox only.

## Always call through the wrapper

```bash
bash {baseDir}/scripts/alpaca.sh <command> [args]
```

The wrapper loads `ALPACA_API_KEY` and `ALPACA_API_SECRET` from `pass` (exporting the second as `ALPACA_SECRET_KEY`, the name the CLI expects), refuses `--live`, refuses any `--profile` other than `paper`, and whitelists commands to read-only calls. Never call the bare `alpaca` binary for anything other than `--help`.

## Common calls

All examples: `AP="bash {baseDir}/scripts/alpaca.sh"`.

```bash
# Connectivity
$AP doctor                                                    # config, credentials, and API reachability, with a JSON-free human report

# Account and positions
$AP account get --jq '.status,.currency'
$AP account get --schema                                      # print the response schema instead of calling the API
$AP position list
$AP position get --symbol-or-asset-id AAPL

# Orders (read only; submit/cancel/replace are blocked by the wrapper)
$AP order list --status all --limit 20
$AP order get --order-id <id>

# Historical stock data (SIP, Basic plan, 15 min delayed)
$AP data bars --symbol AAPL --timeframe 1Day --start 2026-09-01 --end 2026-09-20 --feed sip
$AP data quotes --symbol AAPL --start 2026-09-20 --feed sip
$AP data trades --symbol AAPL --start 2026-09-20 --feed sip
$AP data news --symbols AAPL,MSFT --limit 10

# Market schedule
$AP calendar market --start 2026-09-01 --end 2026-09-30
$AP clock

# Reference data
$AP asset get --symbol-or-asset-id AAPL
$AP corporate-action list --ca-types cash_dividend --symbol AAPL --since 2026-01-01 --until 2026-12-31

# Raw API access (GET only; the wrapper blocks POST/PUT/PATCH/DELETE)
$AP api GET /v2/account
$AP api /v2/positions --jq '.[].symbol'
```

## Gotchas

- Env vars do not persist between Bash tool calls. Always go through the wrapper, which reloads the secrets and exports `ALPACA_SECRET_KEY` inside the same command.
- The CLI defaults to paper when `ALPACA_API_KEY`/`ALPACA_API_SECRET` are set with no profile file; there is nothing to configure.
- `alpaca update` is blocked by the wrapper. Upgrade by downloading the new `cli_<version>_linux_amd64.tar.gz` release from `github.com/alpacahq/cli/releases` and replacing the binary in `~/.local/bin` by hand; there is no build toolchain on this host.
- `--schema` prints the JSON shape of a command's response and exits without calling the API. Useful before writing a `--jq` filter.
- The newest 15 minutes of SIP history is withheld on the Basic plan, so a `data bars`/`quotes`/`trades` call with `--end` near now returns nothing for that window.
- `--feed sip` is worth specifying explicitly on historical calls; some data commands default to a feed that is not SIP.

## Credentials

- `openclaw/ALPACA_API_KEY` and `openclaw/ALPACA_API_SECRET` in `pass`, loaded by the wrapper via `skill_require`. See the credential-storage skill for how to add or rotate them.
- These keys are scoped to the paper account and the data API only. They are never used for live trading.
- Never print key values. `check.sh` reports presence by name only.

## Relation to other skills and the trading bot

- `ibkr` is the sibling skill for the actual broker (Interactive Brokers, paper account, read-only). Alpaca never places trades; it only supplies market data and a sandbox account for testing.
- The trading bot's own Alpaca loader (`src/trading_bot/data/loaders/alpaca.py`) calls the Alpaca REST API directly with the `alpaca-py` SDK, not this CLI. This skill is for interactive/ad hoc lookups and diagnostics, not for the bot's runtime data path.
