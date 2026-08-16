# exec-approvals.json — annotated

JSON has no comments, so this file documents the blocks in `openclaw/exec-approvals.json`. It is the repo's portable copy of the exec approvals policy; `openclaw/apply-approvals.sh` merges it into the live `~/.openclaw/exec-approvals.json`, which additionally carries a `socket` block (IPC path + auth token) that never belongs in the repo.

Schema reference: https://docs.openclaw.ai/tools/exec-approvals

## Policy

There are no more per-command approvals. `defaults.security: "full"` + `ask: "off"` means every agent not explicitly overridden runs exec commands silently — no allowlist, no on-miss prompt, no per-command judgment made at the approvals layer at all. Destructive-command gating is done entirely out-of-band, by the `agent-config-guards` OpenClaw plugin's `before_tool_call` guard (`openclaw/plugins/agent-config-guards/rules.js`'s `checkDestructiveExec`, a mirror of `claude/hooks/block-destructive-bash.sh`): it inspects the actual command text on every exec call and returns `deny` for catastrophic/exfiltration/gate-tampering commands, `requireApproval` (OpenClaw's ask-equivalent) for a short list of commands that are genuinely destructive but recoverable, and lets everything else through silently. `askFallback: "deny"` is kept as a defensive fallback for whatever residual approval surface still exists (an unattended/headless run with no UI to prompt denies rather than hanging or auto-allowing), but under `ask: "off"` it is no longer a live path for ordinary agent work.

**Schema correction (unchanged from before)**: the `security` field's actual enum on this install (verified via `openclaw config schema`, `properties.tools.properties.exec.properties.security`) is `deny | allowlist | full` — three values, not five. `"ask"` and `"auto"` are values of a *different*, higher-level `mode` shorthand field (which presumably expands to a security+ask+askFallback combo), not of the raw `security` field this file sets. This still matters now that `defaults.security` is `"full"`: `"full"` is a real enum value (unrestricted exec, no allowlist gate), confirmed via the same schema lookup used when this was first diagnosed.

## Craftsman-class agents: `main`, `orchestrator`, `craftsman`, `scout`

No entry under `agents` for any of these four — they inherit `defaults` (`security: "full"`, `ask: "off"`, `askFallback: "deny"`) unmodified. The per-agent allowlists and `security: "allowlist"` overrides this file used to carry (narrow `argPattern`s for git/rg/grep/find/python3/node/npm/etc.) are gone entirely: with the guard plugin doing 100% of the destructive-command judgment for every exec call these agents make, a static per-command allowlist here was redundant defense that only added maintenance surface without changing the effective policy.

## Read-only-role agents: `researcher`, `librarian`, `writer`, `planner`, `preplanner`, `reviewer`, `thinker`

```json
{ "security": "deny" }
```

`security: "deny"` blocks all host execution requests outright, regardless of `ask`/`askFallback` — these agents have no legitimate reason to shell out (per their tool roster in `~/.claude/CLAUDE.md`: no `Bash` tool), so exec is denied at the approvals layer too, defense-in-depth against a compromised or misconfigured agent trying to invoke `exec`/`process` anyway. This block is unchanged by the move to `security: "full"` defaults: these seven agents keep `deny`, they never fall through to the new silent-by-default baseline.

## What's NOT in the repo file

- `socket` (`path` + `token`) — live-only, generated per-install. The apply script preserves whatever is already in `~/.openclaw/exec-approvals.json`.
- `version` — the apply script also preserves the live file's `version` rather than trusting the repo copy, in case the live install has moved to a newer schema version than this repo snapshot assumes.
