# Skill provenance

Where each skill in this directory came from, so a rebuild can reinstall from upstream rather than relying on this vendored copy, and so upstream updates can be pulled deliberately.

Skills are vendored here (committed as files) rather than referenced, so the repo stays self-contained. This file is the record of what is ours and what is someone else's.

## Upstream, verified

| Skill | Upstream | License |
|---|---|---|
| `brainstorming`, `dispatching-parallel-agents`, `executing-plans`, `finishing-a-development-branch`, `receiving-code-review`, `requesting-code-review`, `subagent-driven-development`, `systematic-debugging`, `test-driven-development`, `using-git-worktrees`, `using-superpowers`, `verification-before-completion`, `writing-plans`, `writing-skills` | [obra/superpowers](https://github.com/obra/superpowers) | MIT |
| `caveman` | [juliusbrussee/caveman](https://github.com/juliusbrussee/caveman) | see upstream |
| `grill-me` | [mattpocock/skills](https://github.com/mattpocock/skills), path `skills/productivity/grill-me/`. Install via `/plugin install mattpocock-skills` or `npx skills@latest add mattpocock/skills` | MIT |
| `impeccable` | [pbakaus/impeccable](https://github.com/pbakaus/impeccable). Install via `npx impeccable install` | Apache-2.0 |
| `playwright-cli` | [microsoft/playwright-cli](https://github.com/microsoft/playwright-cli), installed via `npx @playwright/cli install --skills --global` | Apache-2.0 |
| `graphify` | shipped by the `graphify` CLI, installed via `graphify install` | see upstream |

The 14 superpowers skills match upstream directory names exactly. Upstream also ships `diagnosing-superpowers`, which is deliberately not vendored here.

## Stale relative to upstream

Two vendored copies are behind their upstream by more than a version bump, so refreshing them means taking a behaviour change, not just newer text.

`grill-me` is byte-identical (ignoring trailing whitespace) to `mattpocock/skills` at commit `62f43a1`, dated 28/04/2026. Upstream rewrote it on 31/05/2026 into a thin dispatcher that delegates to a separate `grilling` skill, which is not vendored here. Our copy is the self-contained pre-refactor version.

`impeccable` matches the current upstream description word for word but predates its v4 architecture. Upstream is at `4.3.1` and declares `version` and `license` in frontmatter, ours declares neither. Upstream has also removed `scripts/live-server.mjs` and `scripts/design-parser.mjs`, both of which we still carry, and `scripts/live-browser.js` has grown from our 192K to roughly 535K upstream. The current release replaces that script pair with a self-contained binary launcher.

## Authored here

Home grown, no upstream. These encode conventions specific to this estate (keyring service names, ticket key prefixes, account layout), so they are not portable without edits.

| Skill | Notes |
|---|---|
| `atlassian`, `aws`, `betterstack`, `cloudflare`, `datadog`, `github`, `gogcli`, `jumpcloud`, `netbird`, `oci`, `octopus`, `slack`, `trunk`, `vanta` | CLI wrappers, one per integration. Each documents the shell CLI and its auth, and most ship a `check.sh` that verifies the binary and its credentials |
| `comms-style` | Outbound text style rules, per medium |
| `sre-tools` | `ecs-diag.sh`, spawns a temporary SSM-enabled diagnostic Fargate container cloned from a target ECS service |
| `web-access` | Three-layer fetch escalation: WebFetch, then `playwright-cli`, then Fortress ([tiliondev/fortress](https://github.com/tiliondev/fortress), BSD 3-Clause) |
| `terraform-lsp` | Not a skill, a Claude Code plugin declaring an `lspServers` entry for `terraform-ls`. Covers `.tf`, `.tfvars` and `.hcl` |

## Excluded from version control

`atlassian/node_modules` (46M) is not tracked. Run `npm install` in that directory after deploying. The harness-managed `synced/` directory is not tracked either, and `apply-skills.sh` skips it.
