# agent-config-guards

OpenClaw plugin that gives the OpenClaw Gateway the same "hard layer" of
guardrails the sibling Claude Code install gets from `claude/hooks/*.sh` and
the live `~/.claude/hooks/*.sh` scripts — in OpenClaw's own hook system.

## Why a plugin, not a managed `HOOK.md` hook

OpenClaw has two hook surfaces (see `docs/automation/hooks.md` and
`docs/plugins/hooks.md`):

- **Managed internal hooks** (`~/.openclaw/hooks/<name>/HOOK.md` + `handler.js`)
  only receive coarse `command:*`, `session:compact:*`, `session:patch`,
  `agent:bootstrap`, `gateway:*`, `message:*` events, and can only push
  `event.messages` into a reply. They **cannot block or gate a tool call**.
- **Typed plugin hooks** (`api.on(hookName, handler, opts)`, registered from a
  plugin's `register(api)`) can return `{ block, blockReason }` or
  `{ requireApproval }` from `before_tool_call`, and `{ prependSystemContext,
  appendSystemContext, ... }` from prompt-build hooks.

Since every guard below needs to block or gate a tool call (the entire point
of the hard layer), this had to be a plugin, not a managed hook.

## Hook -> handler map

| Claude Code hook (`claude/hooks/*.sh` or live `~/.claude/hooks/*.sh`) | OpenClaw hook | Handler in `index.js` | Semantic differences |
| --- | --- | --- | --- |
| `block-destructive-bash.sh` (PreToolUse/Bash) | `before_tool_call`, matcher `exec`/`process`/`code_execution` | destructive-exec guard | Claude's `ask` maps to OpenClaw's `requireApproval` (`severity: "warning"`, `timeoutBehavior: "deny"`); Claude's `deny` maps to `{ block: true, blockReason }`. Regexes are byte-for-byte ports (`[[:space:]]` -> `\s`, `\b` unchanged) — see `rules.js` `EXEC_DENY_RULES` / `EXEC_ASK_RULES`. |
| `write-path-guard.sh` (PreToolUse/Write\|Edit\|MultiEdit\|NotebookEdit) | `before_tool_call`, matcher `write`/`edit`/`apply_patch` | write-path guard | Same protected-path set, `deny`/`ask` -> `block`/`requireApproval`. "cwd" becomes `ctx.workspaceDir` (falls back to `process.cwd()`); "`/tmp/claude-*` scratchpad" allowance is kept (subagents still write there) plus `os.tmpdir()`, gated by the `workspaceOnlyWrites` config flag. |
| `write-existing-file-guard.sh` (PreToolUse/Write) | `after_tool_call` on `read`/`edit`/`write` (records) + `before_tool_call` on `write` (denies) | write-existing-file guard | Claude reads the JSONL transcript to check prior `Read`/`Edit` calls (including subagent transcripts). OpenClaw has no equivalent transcript file exposed to plugins, so this guard keeps its own per-`sessionKey` `Set` of paths, updated via `after_tool_call`, persisted (best-effort, debounced) to `~/.openclaw/state/agent-config-guards/read-history.json` so a Gateway restart mid-session doesn't reopen the hole. Same fail-open contract: no `sessionKey`, no existing file, or unreadable state -> allow. |
| `compaction-context-injector.sh` (SessionStart/compact, SubagentStart) | `before_prompt_build` | context re-injection (system half) | Claude re-injects on compaction/subagent-start events specifically. OpenClaw's `before_prompt_build` fires every turn and supports `prependSystemContext`/`appendSystemContext`, which the docs say are cached for the provider (prompt caching) — closer to "standing directive" semantics than the per-turn `agent_turn_prepare.appendContext`, so the boundary text lives here instead. |
| `caveman-inject.sh` (SessionStart, SubagentStart) | `before_prompt_build` (same handler as above) | context re-injection | Folded into the same `prependSystemContext` call, gated by plugin config `caveman: true` or `OPENCLAW_CAVEMAN=1` (per the task spec) instead of always-on. |
| `agent-usage-reminder.sh` (UserPromptSubmit, keyword-triggered) | `before_prompt_build` (same handler), `ctx.agentId` check | context re-injection | Claude's version keyword-matches the prompt text per turn. This port is static: it appends the delegation reminder whenever `ctx.agentId` is `main` or `orchestrator`, every turn, rather than keyword-matching — `before_prompt_build` does not expose a cheap way to keyword-scan the *next* user prompt before the model call the way `UserPromptSubmit` does. Flagged as a simplification, not a byte-for-byte port. |
| `bash-file-read-guard.sh` (PreToolUse/Bash, non-blocking) | `before_tool_call`, matcher `exec` | file-read nudge | Never blocks in either implementation. Claude injects `additionalContext` synchronously into the *same* PreToolUse response. OpenClaw's `before_tool_call` result shape (`PluginHookBeforeToolCallResult`) has no context-injection field, so the nudge is stashed per-`sessionKey` and delivered on the *next* `agent_turn_prepare` via `appendContext` instead of immediately. |
| `auto-format.sh` (PostToolUse/Write\|Edit\|MultiEdit) | `after_tool_call` on `write`/`edit` | auto-format | Same formatter table (prettier/ruff/gofmt/rustfmt/shfmt/rubocop), same "skip silently if the binary is missing" behavior. Runs fire-and-forget (not awaited) so it can never slow down or fail the tool call. |
| `comment-checker.sh` (PostToolUse/Write\|Edit) | `after_tool_call` on `write`/`edit` (detect) + `agent_turn_prepare` (deliver) | comment-checker | Same regex and same skip-list of doc/config extensions. Claude injects `additionalContext` directly from PostToolUse. OpenClaw's `after_tool_call` is observation-only (no result fields at all), so the warning is stashed per-`sessionKey` and delivered via the next `agent_turn_prepare`'s `appendContext`, same mechanism as the file-read nudge. |
| `session-notification.sh` (Stop, SubagentStop, Notification) | `session_end`, `agent_end` | session-notification | Claude's `Notification`/`Stop`/`SubagentStop` events don't have a clean OpenClaw equivalent per-event; this uses `session_end` (session lifecycle boundary) and `agent_end` (turn boundary) instead, and reads the notify command from plugin config `notifyCommand` (default: no-op, since `notify-send` presence isn't probed at hook-registration time the way the shell script's `command -v` check runs per-invocation — this JS port also checks presence, but only lazily by letting `execFile` fail silently if the binary is missing). |
| *(none — new)* `claude/hooks/webfetch-domain-guard.sh` spec | `before_tool_call`, matcher `web_fetch`/`web_search`/`browser` | webfetch-domain guard | Built directly from the task's spec (the sibling Claude hook did not exist yet when this plugin was written — see "Unverifiable / deviations" below). Scans the **entire stringified `params`** for URLs and secret patterns rather than one named field, since the exact per-tool field name (`url` vs something else) wasn't confirmed for every matched tool. |
`claude/hooks/outbound-guard.sh` (landed after this guard was already implemented from the task's inline spec — see deviation note below) | `before_tool_call` matcher `message`/`sessions_send` (gate) + `message_sending` (observe) | outbound guard | See "message vs message_sending" below — only the `message`/`sessions_send` **tool call** is gated; `message_sending` is observe-only + logged, per the task's explicit fallback instruction. |

## `message` tool vs `message_sending` hook

The task asked me to figure out, from the event fields, how to tell "the
normal reply to the current chat" apart from "a proactive send to a different
target," and to gate only the `message` tool if I couldn't.

I couldn't, for `message_sending` specifically: `PluginHookMessageSendingEvent`
is `{ to, content, replyToId?, threadId?, metadata? }` and its context is
`PluginHookMessageContext` (`channelId`, `sessionKey`, ...). `to` is populated
for **every** outbound send, including the normal turn reply — it's the
delivery destination, not a marker for "this is unusual." There is no field
that says "this is the model's synthesized final answer to the current
conversation" vs "this is a `message` tool call the model made mid-turn to
some other target." Cancelling on `message_sending` using any heuristic over
`to` risks blocking the normal reply, which the task explicitly said not to
do.

The `message` (and `sessions_send`) **tool call**, on the other hand, is
model-initiated and explicit: `before_tool_call`'s `event.params` is the
literal arguments the model chose, and `ctx.sessionKey`/`ctx.channelId`/
`ctx.chatId` are the current conversation's identity. So the outbound guard
compares a target field on the tool params (`to`/`target`/`sessionKey`/
`channel`/`channelId`/`chatId` — checked in that order, see
`rules.js#extractOutboundTarget`) against those three context fields; a
mismatch means "explicit target that isn't this conversation" ->
`requireApproval` with `severity: "critical"`. No target field present ->
treated as the normal reply -> allow (fail open, consistent with every other
guard's fail-open contract).

`message_sending` stays registered as observe-only: it logs one line per
outbound send (`to`, `sessionKey`) for audit visibility, and returns nothing
(no `cancel`).

## Unverifiable / deviations

Flagged explicitly, as raw facts rather than folded silently into the code:

- **`claude/hooks/webfetch-domain-guard.sh` and `outbound-guard.sh` did not
  exist yet** when this plugin was started (checked `claude/hooks/` at the
  start of this task — only the five original hook scripts plus
  `.orig-backup` were present). Both were built from the task's inline spec
  first, then re-checked once the other agent's work landed mid-task:
  - `webfetch-domain-guard.sh` landed with behavior matching the task's spec
    closely enough that `rules.js#checkWebfetchGuard` was rewritten to port it
    byte-for-byte (see the comment at the top of that function) — same secret
    checks, same textual SSRF regex, same non-https/denylist ask-tier, same
    per-tool-name target field (`WebFetch`→`url`, `WebSearch`→`query`,
    MCP-like→`url`/`uri`), mapped onto `web_fetch`→`url`,
    `web_search`→`query`, `browser`→`url` (falling back to stringified params
    for non-navigate browser actions, since Claude has no `browser` tool
    equivalent).
  - `outbound-guard.sh` landed with a **different design** than this plugin's
    outbound guard, and was deliberately **not** re-ported, flagged here
    instead of silently diverging: the Claude script's rule is "always ASK
    for `SendMessage`/outward-posting MCP tools, *except* when the target
    looks like an internal subagent handoff" (a generated hex id ≥15 chars,
    or a name matching `~/.claude/agents/*.md`). Claude's `SendMessage` is
    itself an agent-to-agent tool (closer to OpenClaw's `sessions_send` than
    to OpenClaw's `message`, which is specifically channel/person delivery).
    This plugin instead asks only when the tool's target field
    (`to`/`target`/`sessionKey`/`channel`/`channelId`/`chatId`) differs from
    the current `ctx.sessionKey`/`ctx.channelId`/`ctx.chatId` — i.e.
    same-conversation replies are always silent, cross-conversation sends
    always ask, and there is no separate "internal handoff" allowlist. I did
    not have a verified way to build an OpenClaw-side equivalent of "looks
    like an internal subagent session key" (no confirmed doc for
    `sessions_spawn`'s child `sessionKey` naming convention), so porting the
    Claude script's exact allowlist logic risked either being permanently
    over-strict (asking on every legitimate `sessions_send` to a spawned
    child) or silently under-strict (a wrong allowlist regex that lets real
    exfiltration through). The mismatch-based heuristic already implemented
    is more conservative in one direction (never silently allows a genuinely
    different target) and more permissive in another (a `sessions_send` to a
    freshly spawned child session will ask once, where Claude's version would
    stay silent for it) — flagging this as a real behavioral difference, not
    a rounding error.
- **Exact `write`/`edit` tool parameter field name.** Docs confirmed `exec`'s
  `command`, `apply_patch`'s single `input` patch-text string (no direct path
  param — hence `event.derivedPaths` exists specifically for it), and
  `web_fetch`'s `url`, but no primary-source doc for `write`/`edit`'s path
  field turned up in `/usr/lib/node_modules/openclaw/docs/tools/`. `index.js`
  `extractToolPath()` checks `path`, `file_path`, `filePath`,
  `notebook_path`, then falls back to `event.derivedPaths[0]`. Verify the real
  field name with `openclaw plugins inspect agent-config-guards --runtime
  --json` plus a live `write` call, or by reading
  `dist/extensions/*` tool-registration source, and simplify
  `extractToolPath` to the one true key if it differs from all of these.
- **`openclaw/plugin-sdk/plugin-entry` import resolution from a `--link`'ed
  local plugin directory** was not provable without a live install. Tested
  `require.resolve('openclaw/plugin-sdk/plugin-entry')` and plain ESM
  `import` from an arbitrary directory outside `~/.openclaw/plugins/` and
  both failed (no local `node_modules/openclaw`, and `openclaw` is only
  globally npm-installed under `/usr/lib/node_modules`, which is not on
  Node's default `require`/`import` resolution path).
  `docs/plugins/dependency-resolution.md` documents that OpenClaw "reasserts
  plugin-local `node_modules/openclaw` links for **installed packages** that
  declare the host peer, after install or update," and separately that local
  plugins are "developer-controlled directories" OpenClaw never touches with
  a package manager — it doesn't say whether a `--link`'ed local directory
  gets that same `node_modules/openclaw` symlink treatment or not. Rather
  than gamble on that, `index.js` avoids importing anything from
  `openclaw/plugin-sdk/*` entirely: `definePluginEntry` (read from
  `dist/plugin-entry-CM_XK0Yw.js`) is confirmed to be a thin
  arguments-with-defaults wrapper, not a hook into anything, so `index.js`'s
  default export is the equivalent plain object instead.
- **Manifest shape.** The task brief's own `plugin.json {id, name, version,
  entry, contracts:{hooks:[...]}}` sketch was explicitly marked
  "verify" — verified against `docs/plugins/manifest.md`,
  `docs/plugins/sdk-entrypoints.md`, and the bundled `extensions/policy/`
  plugin as a real example, and corrected: the manifest file must be
  literally named `openclaw.plugin.json` (not `plugin.json`), there is no
  `entry` field (the JS entry point is declared in `package.json`'s
  `openclaw.extensions` array), and `contracts` has no `hooks` list —
  ordinary `api.on(...)` hook registrations need no manifest declaration at
  all (only `contracts.tools`, `contracts.trustedToolPolicies`, and similar
  *capability* lists are manifest-gated). `configSchema` **is** required.
- **`sessions_send` target field name.** `docs/concepts/session-tool.md`
  documents `sessions_send`'s *behavior* ("send a message to another session")
  but not its exact JSON parameter names. `extractOutboundTarget` checks
  `sessionKey` among its candidate fields on the assumption it matches the
  tool's own vocabulary; verify against a live call if the guard doesn't
  trigger as expected.

## Plugin config

`plugins.entries.agent-config-guards.config`:

```json5
{
  caveman: false, // also settable via OPENCLAW_CAVEMAN=1
  notifyCommand: null, // e.g. "notify-send"; null = no-op
  webfetchDenylist: null, // path; defaults to $OPENCLAW_WEBFETCH_DENYLIST or ~/.openclaw/webfetch-denylist.txt
  protectedPaths: [], // extra paths write-path-guard should deny writes to
  workspaceOnlyWrites: true, // false = only enforce hard-denied protected paths, skip the cwd/workspace ask-tier
}
```

## Testing

`scripts/test-openclaw-guards.mjs` imports `rules.js` directly (no Gateway,
no `api` object) and asserts allow/ask/deny for the same style of cases
`scripts/test-hooks.sh` uses for the Claude hooks, including the
`shared/fixtures/hostile-readme.md` injected command.
