# exec-approvals.json — annotated

JSON has no comments, so this file documents the blocks in `openclaw/exec-approvals.json`. It is the repo's portable copy of the exec approvals policy; `openclaw/apply-approvals.sh` merges it into the live `~/.openclaw/exec-approvals.json`, which additionally carries a `socket` block (IPC path + auth token) that never belongs in the repo.

Schema reference: https://docs.openclaw.ai/tools/exec-approvals

## `defaults`

```json
{ "security": "allowlist", "ask": "on-miss", "askFallback": "deny" }
```

Baseline for any agent not explicitly listed under `agents`. `security: "allowlist"` + `ask: "on-miss"` together mean: run allowlisted commands, prompt for anything else instead of silently running or silently denying it. `askFallback: "deny"` means an unattended/headless run (no UI to prompt) denies rather than hangs or auto-allows.

**Schema correction from the task brief / docs.openclaw.ai prose**: the `security` field's actual enum on this install (verified via `openclaw config schema`, `properties.tools.properties.exec.properties.security`) is `deny | allowlist | full` — three values, not five. `"ask"` and `"auto"` are values of a *different*, higher-level `mode` shorthand field (which does have 5 values and presumably expands to a security+ask+askFallback combo), not of the raw `security` field the exec-approvals file uses. This was caught empirically: writing `security: "ask"` into `~/.openclaw/exec-approvals.json` was silently accepted by `openclaw approvals set` (no validation error) but silently dropped on read-back (`openclaw approvals get --json` round-tripped the agent/defaults object with the `security` key missing entirely), so the effective-policy table kept showing `security=full` (falling through to the unset "requested" side) instead of anything stricter. Re-verified the same round-trip check after switching to `security: "allowlist"` — it persists and the effective table now shows `security=allowlist` for every craftsman-class agent. The `"ask"` *behavior* the task asked for is still achieved, just via `security: "allowlist"` + `ask: "on-miss"` rather than a literal `security: "ask"` value.

## Craftsman-class agents: `main`, `orchestrator`, `craftsman`, `scout`

These four don't restate `ask`/`askFallback` (inherited from `defaults`) but do set `security: "allowlist"` explicitly per-agent, in addition to their own `allowlist` array. The explicit per-agent `security` is not redundant with `defaults.security` — see the schema-correction note above; per-agent `security` was confirmed (empirically) to survive the round-trip, so it's the reliable lever, not the file-level default. Allowlists are per-agent, so one agent's trusted commands never leak into another's policy. Every entry is `{pattern, argPattern?}`; `pattern` uses the `**/<cmd>` glob form (matches the resolved absolute path of the binary, robust regardless of which PATH directory it's found in) rather than the bare-name form, per the example given in the task brief. Commands that don't match any entry fall through to `ask` (`on-miss`), i.e. the user is prompted — nothing silently executes and nothing is silently blocked.

Entries, and the judgment calls behind them:

- **git** — allowed except `push`, `clean`, or `reset --hard`, via negative lookahead on the joined arg string. This is exactly what the task asked for; note the regex is a blocklist, not an allowlist of git subcommands, so it still permits `add`/`commit`/`checkout`/`merge`/`rebase`/etc. Flagging this as broader than "read-only" — it's "no history-destroying / no remote-push" rather than strictly read-only.
- **rg, grep, ls, cat, head, tail, wc, jq** — unrestricted args; all read-only tools with no destructive flags worth blocking.
- **find** — task listed it unrestricted, but `find` supports `-delete`, `-exec`, `-execdir`, `-fprint` which turn it into an arbitrary delete/exec primitive. Added an argPattern excluding those four flags. This is a deliberate deviation from the literal task list, done for safety; flagging it rather than doing it silently.
- **python3, node, npm, pnpm, make, cargo, go** — argPattern restricts the arg string to start with `test|build|run|--version|list|check` (plus `version` without dashes for `go`, since `go version` — not `go --version` — is the real subcommand). This is deliberately narrow: it blocks e.g. `python3 -c '...'`, `node script.js`, `npm install`. That's the literal scope the task specified; broader dev-loop commands (installs, arbitrary scripts) still fall through to `ask`.
- **docker** — restricted to `ps`, `logs`, and `compose ps` (read-only inspection, no `run`/`exec`/`rm`/`compose up`).
- **ssh** — intentionally omitted. No `argPattern` can safely bound what a remote command can do (the remote side has its own shell), so per the task's "only if pattern-safe else omit" instruction, it's left off. Falls through to `ask`.

## Read-only-role agents: `researcher`, `librarian`, `writer`, `planner`,
## `preplanner`, `reviewer`, `thinker`

```json
{ "security": "deny" }
```

`security: "deny"` blocks all host execution requests outright, regardless of `ask`/`askFallback`/allowlist — these agents have no legitimate reason to shell out (per their tool roster in `~/.claude/CLAUDE.md`: no `Bash` tool), so exec is denied at the approvals layer too, defense-in-depth against a compromised or misconfigured agent trying to invoke `exec`/`process` anyway.

## What's NOT in the repo file

- `socket` (`path` + `token`) — live-only, generated per-install. The apply script preserves whatever is already in `~/.openclaw/exec-approvals.json`.
- `version` — the apply script also preserves the live file's `version` rather than trusting the repo copy, in case the live install has moved to a newer schema version than this repo snapshot assumes.
