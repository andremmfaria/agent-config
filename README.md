# Agent Config

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Reusable agent instruction files for OpenClaw and Claude Code.

This repo tracks durable prompt and policy surfaces: role definitions, safety rules, and portable terminal-agent configuration. It deliberately does not track memory, credentials, runtime sessions, logs, or environment-specific secret files.

## Layout

```text
openclaw/workspace/          Main OpenClaw workspace instruction files
openclaw/agents/             OpenClaw specialist AGENTS.md, SOUL.md, and IDENTITY.md files
openclaw/openclaw.json       Portable OpenClaw-style agent configuration
claude/                      Claude Code global prompt, agents, and output styles
claude/claude.json           Portable Claude-style agent configuration
scripts/                     Sync and validation helpers
private/                     Ignored local-only drop zone; only private/README.md is tracked
```

## What Belongs Here

- `AGENTS.md`, `SOUL.md`, `IDENTITY.md`, `HEARTBEAT.md`
- specialist agent role prompts, souls, and identities
- Claude Code `CLAUDE.md`, agent prompts, and output styles
- sync/check scripts
- portable runtime configuration JSON
- implementation instructions for another agent

## What Does Not Belong Here

- `TOOLS.md`
- `MEMORY.md`
- `USER.md` with real personal details
- daily notes under `memory/`
- session transcripts and logs
- credentials, API keys, cookies, tokens, host-specific secrets
- files under `private/` other than `private/README.md`

## Directory Status

`private/` is useful and should stay. It is an ignored landing pad for local-only notes about what must not be committed. Git tracks only `private/README.md`; `.gitignore` excludes the rest of the directory.

## Sync

Preview what would change:

```bash
./scripts/sync-config.sh --dry-run
```

Synchronize tracked repo files with the live OpenClaw and Claude Code config:

```bash
./scripts/sync-config.sh
```

The sync script only manages files tracked in this repo. It compares hashes first, skips files that already match, and only backs up the side it is about to overwrite under `~/.agent-config-backups/<timestamp>/`. Set `AGENT_CONFIG_BACKUP_DIR` to override that location.

Important: sync is not a one-way deploy. When a repo file and its live copy both exist but differ, the script asks what to do. The default is live wins, which copies the live file back into the repo. Choose repo wins when you are deliberately deploying repo-authored prompt edits.

The script also materializes old symlinks as regular files.

After the file sync completes, `sync-config.sh` automatically invokes both apply-agents scripts to push agent definitions into each platform's live config. Pass `--dry-run` to both scripts together; the sync dry-run propagates to the agent-apply step.

## Apply Agents

Two separate scripts handle agent installation, one per platform:

### OpenClaw: `openclaw/apply-agents.sh`

Performs an idempotent JSON upsert of the repo agent definitions (`openclaw/openclaw.json`) into `~/.openclaw/openclaw.json`.

```bash
# Dry-run: print merged JSON to stdout, write nothing
./openclaw/apply-agents.sh --dry-run

# Apply for real (backs up live file first)
./openclaw/apply-agents.sh
```

Live-only fields (fallbacks, skills, subagents, thinkingDefault, workspace) are preserved during upsert via recursive merge. New agents are appended; existing agents stay in their original order. If the merged JSON matches the live file, the script prints `unchanged` and does not back up or rewrite it.

### Claude Code: `claude/apply-agents.sh`

Copies each `claude/agents/*.md` file into `~/.claude/agents/`. Claude Code reads agent definitions exclusively from markdown files in that directory. It does not read them from any JSON config. Matching files are reported as `unchanged` and are not backed up or rewritten.

```bash
# Dry-run: print what would be copied, write nothing
./claude/apply-agents.sh --dry-run

# Apply for real (backs up any existing destination files first)
./claude/apply-agents.sh
```

## Verify

```bash
./scripts/check-sync.sh
```

This checks that all expected live OpenClaw and Claude Code instruction files are regular files and match the repo copies.

---

## Implementation Guide (for AI agents)

> This section contains machine-facing instructions for an AI agent implementing or recreating the setup described in this repository. It is intentionally terse and directive.

Use this repository as a portable, sanitized agent-definition source. Do not add machine-specific capabilities, hostnames, IP addresses, secrets, private memory, session logs, or personal environment notes to this repository.

### Inputs

- `openclaw/openclaw.json` describes the workspace and specialist agent layout for the OpenClaw-style runtime.
- `claude/claude.json` describes the global prompt, default output style, and specialist subagents for the Claude-style runtime.
- `openclaw/` and `claude/` contain the referenced prompt files.

### Implementation Rules

1. Create the agent directories declared in the relevant JSON file.
2. Copy the referenced prompt files exactly.
3. Keep runtime-local files outside the repository. Examples include real user profiles, machine-specific tools, credentials, memory, logs, sessions, and service endpoints.
4. Preserve the untrusted-content boundary in every agent prompt.
5. Preserve the agent names, roles, delegation map, and planning pipeline.
6. For Claude-style agents, use only the model tiers declared in `claude/claude.json`; do not add primary-runtime model names there.
7. For OpenClaw-style agents, keep model comparisons only in the OpenClaw-side files and config.
8. After installing, run `./scripts/check-sync.sh` to confirm live files match the repository copies. Use `./scripts/sync-config.sh --dry-run` before applying sync, then choose the sync direction explicitly for any differing files.

### Conflict Policy

If live local files differ from the repository, prefer the live local file only when it contains intentional private or machine-specific data. Otherwise, update the live file from the repository.

Never copy local private data back into this repository.
