// index.js — agent-config-guards OpenClaw plugin entry point.
//
// Registers the OpenClaw plugin hooks that give this Gateway the same "hard
// layer" of guardrails the sibling Claude Code install gets from
// claude/hooks/*.sh. See README.md for the full mapping and the reasoning
// behind each hook choice (managed HOOK.md hooks can't block tool calls, so
// every blocking/approval guard here is a typed plugin hook via api.on(...)).
//
// Handlers are thin: all decision logic lives in rules.js as pure functions,
// so scripts/test-openclaw-guards.mjs can exercise the same code path this
// file wires up, without a running Gateway.
//
// definePluginEntry from openclaw/plugin-sdk/plugin-entry is intentionally
// NOT imported here. It is a typing/defaulting convenience only (verified by
// reading dist/plugin-entry-CM_XK0Yw.js: it just spreads its arguments over
// a defaults object) — importing "openclaw/plugin-sdk/*" from a locally
// linked plugin directory depends on OpenClaw's plugin loader providing that
// module resolution, which docs/plugins/dependency-resolution.md documents
// clearly for npm/git installs but leaves unstated for `--link`'ed local
// directories. Exporting a plain object sidesteps that risk entirely.

import { existsSync, readFileSync, writeFileSync, mkdirSync, realpathSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";
import { execFile, execFileSync } from "node:child_process";

import {
  checkDestructiveExec,
  checkWritePathGuard,
  resolvePathLexical,
  checkWriteExistingFile,
  checkWebfetchGuard,
  parseDenylistFile,
  checkOutboundGuard,
  checkFileReadNudge,
  checkCommentDensity,
  buildSystemContext,
  buildTurnContext,
} from "./rules.js";

const HOME = homedir();
const STATE_DIR = join(HOME, ".openclaw", "state", "agent-config-guards");
const READ_HISTORY_FILE = join(STATE_DIR, "read-history.json");

// ---------------------------------------------------------------------------
// Per-session state (in-memory; read-history additionally persisted so a
// Gateway restart mid-session doesn't reopen the write-existing-file hole).
// ---------------------------------------------------------------------------

/** sessionKey -> Set<absolute path Read/Edited this session> */
const seenPaths = new Map();
/** sessionKey -> string[] pending notices for the next agent_turn_prepare */
const pendingNotices = new Map();

function loadReadHistory() {
  try {
    const raw = readFileSync(READ_HISTORY_FILE, "utf8");
    const parsed = JSON.parse(raw);
    for (const [sessionKey, paths] of Object.entries(parsed)) {
      seenPaths.set(sessionKey, new Set(paths));
    }
  } catch {
    // Missing/corrupt state file -> start empty. Fail-open, matches the
    // write-existing-file guard's own fail-open contract.
  }
}

let saveScheduled = false;
function saveReadHistory() {
  if (saveScheduled) return;
  saveScheduled = true;
  setTimeout(() => {
    saveScheduled = false;
    try {
      mkdirSync(STATE_DIR, { recursive: true });
      const out = {};
      for (const [sessionKey, paths] of seenPaths.entries()) out[sessionKey] = [...paths];
      writeFileSync(READ_HISTORY_FILE, JSON.stringify(out), "utf8");
    } catch {
      // Best-effort persistence only; in-memory state still works this run.
    }
  }, 250).unref?.();
}

function stashNotice(sessionKey, text) {
  if (!sessionKey || !text) return;
  const list = pendingNotices.get(sessionKey) || [];
  list.push(text);
  pendingNotices.set(sessionKey, list);
}

function drainNotices(sessionKey) {
  if (!sessionKey) return [];
  const list = pendingNotices.get(sessionKey);
  pendingNotices.delete(sessionKey);
  return list || [];
}

// ---------------------------------------------------------------------------
// Path resolution helpers (fs-aware layer on top of rules.js's pure lexical
// resolver).
// ---------------------------------------------------------------------------

function resolveAbsolute(inputPath, cwd) {
  if (!inputPath) return "";
  let p = resolvePathLexical(inputPath, HOME);
  if (!p.startsWith("/")) p = resolvePathLexical(join(cwd || process.cwd(), p), HOME);
  try {
    // Follow symlinks along any existing prefix, same intent as
    // write-path-guard.sh's `realpath -m`.
    if (existsSync(p)) return realpathSync(p);
  } catch {
    // fall through to lexical path
  }
  return p;
}

/** Best-effort path extraction: OpenClaw's write/edit tool param naming
 * wasn't confirmed against a primary doc during implementation (only
 * apply_patch's `input`-string shape and web_fetch's `url` were confirmed),
 * so this checks the plausible candidates plus the host-derived
 * `derivedPaths` hint. See README "Unverifiable / deviations". */
function extractToolPath(params, derivedPaths) {
  if (params && typeof params === "object") {
    for (const key of ["path", "file_path", "filePath", "notebook_path"]) {
      if (typeof params[key] === "string" && params[key]) return params[key];
    }
  }
  if (Array.isArray(derivedPaths) && derivedPaths.length > 0) return derivedPaths[0];
  return undefined;
}

const whichCache = new Map();
function which(bin) {
  if (whichCache.has(bin)) return whichCache.get(bin);
  let found = false;
  try {
    execFileSync("command", ["-v", bin], { shell: "/bin/sh" });
    found = true;
  } catch {
    found = false;
  }
  whichCache.set(bin, found);
  return found;
}

// ---------------------------------------------------------------------------
// Plugin registration
// ---------------------------------------------------------------------------

function register(api) {
  loadReadHistory();

  const cfg = api.pluginConfig || {};
  const caveman = cfg.caveman === true || process.env.OPENCLAW_CAVEMAN === "1";
  const notifyCommand = Object.prototype.hasOwnProperty.call(cfg, "notifyCommand")
    ? cfg.notifyCommand
    : null;
  const protectedExtra = Array.isArray(cfg.protectedPaths) ? cfg.protectedPaths : [];
  // workspaceOnlyWrites (default true): widens the in-scope set for the
  // write-path guard beyond cwd/workspace to also include /tmp/claude-* and
  // the OS tmpdir. This only affects which paths count as "in scope" at all;
  // the ask-vs-allow decision for anything out of scope is separately gated
  // by whether the target file already exists (see checkWritePathGuard's
  // fileExists param) — creating a brand-new file outside the workspace is
  // never asked about, only overwriting one that already exists there is.
  const workspaceOnlyWrites = cfg.workspaceOnlyWrites !== false; // default true

  let denylistPatterns = [];
  const denylistPath =
    cfg.webfetchDenylist || process.env.OPENCLAW_WEBFETCH_DENYLIST || join(HOME, ".openclaw", "webfetch-denylist.txt");
  try {
    denylistPatterns = parseDenylistFile(readFileSync(denylistPath, "utf8"));
  } catch {
    denylistPatterns = []; // optional file; absence is normal
  }

  const log = (hook, decision, detail) => {
    const line = `[agent-config-guards] ${hook} -> ${decision}${detail ? `: ${detail}` : ""}`;
    if (api.logger && typeof api.logger.info === "function") api.logger.info(line);
    else console.log(line);
  };

  // -- a. destructive-exec guard --------------------------------------------
  api.on(
    "before_tool_call",
    (event) => {
      const command = event.params && (event.params.command || event.params.input);
      const result = checkDestructiveExec(typeof command === "string" ? command : "");
      if (result.decision === "allow") return;
      log("destructive-exec-guard", result.decision, result.ruleId);
      if (result.decision === "deny") return { block: true, blockReason: result.reason };
      return {
        requireApproval: {
          title: "Confirm command",
          description: result.reason,
          severity: "warning",
          timeoutMs: 120_000,
          timeoutBehavior: "deny",
        },
      };
    },
    { priority: 90, matcher: ["exec", "process", "code_execution"] },
  );

  // -- b. write-path guard ---------------------------------------------------
  api.on(
    "before_tool_call",
    (event, ctx) => {
      const rawPath = extractToolPath(event.params, event.derivedPaths);
      if (!rawPath) return;
      const cwd = ctx.workspaceDir || process.cwd();
      const resolved = resolveAbsolute(rawPath, cwd);
      const result = checkWritePathGuard({
        path: resolved,
        cwd: resolvePathLexical(cwd, HOME),
        homeDir: HOME,
        protectedExtra,
        scratchPrefixes: workspaceOnlyWrites ? ["/tmp/claude-", tmpdir() + "/"] : [],
        fileExists: existsSync(resolved),
      });
      if (result.decision === "allow") return;
      log("write-path-guard", result.decision, resolved);
      if (result.decision === "deny") return { block: true, blockReason: result.reason };
      return {
        requireApproval: {
          title: "Write outside workspace",
          description: result.reason,
          severity: "warning",
          timeoutMs: 120_000,
          timeoutBehavior: "deny",
        },
      };
    },
    { priority: 85, matcher: ["write", "edit", "apply_patch"] },
  );

  // -- c. write-existing-file guard ------------------------------------------
  api.on(
    "before_tool_call",
    (event, ctx) => {
      if (event.toolName !== "write") return;
      const rawPath = extractToolPath(event.params, event.derivedPaths);
      if (!rawPath) return;
      const cwd = ctx.workspaceDir || process.cwd();
      const resolved = resolveAbsolute(rawPath, cwd);
      const sessionKey = ctx.sessionKey;
      const result = checkWriteExistingFile({
        path: resolved,
        sessionKey,
        seenPaths: sessionKey ? seenPaths.get(sessionKey) : undefined,
        fileExists: existsSync(resolved),
      });
      if (result.decision === "allow") return;
      log("write-existing-file-guard", result.decision, resolved);
      return { block: true, blockReason: result.reason };
    },
    { priority: 80, matcher: ["write"] },
  );

  api.on(
    "after_tool_call",
    (event, ctx) => {
      if (event.error || !["read", "edit"].includes(event.toolName)) return;
      const rawPath = extractToolPath(event.params, undefined);
      if (!rawPath || !ctx.sessionKey) return;
      const cwd = ctx.workspaceDir || process.cwd();
      const resolved = resolveAbsolute(rawPath, cwd);
      const set = seenPaths.get(ctx.sessionKey) || new Set();
      set.add(resolved);
      seenPaths.set(ctx.sessionKey, set);
      saveReadHistory();

      // -- g. auto-format (write/edit) & comment-checker share this hook --
      if (event.toolName === "edit") runAutoFormatAndCommentChecker(resolved, ctx.sessionKey);
    },
    { priority: 50 },
  );

  // after_tool_call for write: track it as "seen" too (a fresh write means
  // the agent now knows the file's contents) and run auto-format/comment-checker.
  api.on(
    "after_tool_call",
    (event, ctx) => {
      if (event.error || event.toolName !== "write") return;
      const rawPath = extractToolPath(event.params, event.derivedPaths);
      if (!rawPath) return;
      const cwd = ctx.workspaceDir || process.cwd();
      const resolved = resolveAbsolute(rawPath, cwd);
      if (ctx.sessionKey) {
        const set = seenPaths.get(ctx.sessionKey) || new Set();
        set.add(resolved);
        seenPaths.set(ctx.sessionKey, set);
        saveReadHistory();
      }
      runAutoFormatAndCommentChecker(resolved, ctx.sessionKey);
    },
    { priority: 50 },
  );

  function runAutoFormatAndCommentChecker(filePath, sessionKey) {
    // auto-format: best-effort, fire-and-forget, silent if the binary is missing.
    const fmt = pickFormatter(filePath);
    if (fmt) {
      execFile(fmt.bin, [...fmt.args, filePath], { timeout: 10_000 }, (err) => {
        if (!err) log("auto-format", "formatted", `${filePath} (${fmt.bin})`);
      });
    }

    // comment-checker: warn-only, stashed for next turn.
    try {
      const content = readFileSync(filePath, "utf8");
      const check = checkCommentDensity({ filePath, content, threshold: Number(process.env.COMMENT_CHECKER_THRESHOLD) || 3 });
      if (check.flagged) {
        log("comment-checker", "flagged", `${check.count} in ${filePath}`);
        stashNotice(
          sessionKey,
          `comment-checker flagged ${check.count} likely low-value / AI-filler comments in ${filePath} — comments that restate WHAT the code does. Review and delete the redundant ones; keep only comments that explain WHY. Flagged lines:\n${check.sample}`,
        );
      }
    } catch {
      // File unreadable (race, deleted, binary) -> skip silently.
    }
  }

  function pickFormatter(filePath) {
    const lower = filePath.toLowerCase();
    const table = [
      { exts: [".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs", ".json", ".jsonc", ".css", ".scss", ".less", ".html", ".vue", ".svelte", ".yaml", ".yml", ".md", ".markdown", ".graphql"], bin: "prettier", args: ["--write", "--log-level", "silent"] },
      { exts: [".py"], bin: "ruff", args: ["format", "-q"] },
      { exts: [".go"], bin: "gofmt", args: ["-w"] },
      { exts: [".rs"], bin: "rustfmt", args: [] },
      { exts: [".sh", ".bash"], bin: "shfmt", args: ["-w"] },
      { exts: [".rb"], bin: "rubocop", args: ["-A", "-f", "quiet"] },
    ];
    for (const row of table) {
      if (row.exts.some((ext) => lower.endsWith(ext)) && which(row.bin)) return row;
    }
    return null;
  }

  // -- d. webfetch-domain guard -----------------------------------------------
  // Target field per tool mirrors claude/hooks/webfetch-domain-guard.sh's
  // WebFetch->url / WebSearch->query / MCP-fetch-like->url||uri split.
  // `browser` has no Claude equivalent (OpenClaw-specific addition to the
  // matcher per the task spec); its navigate-style actions carry `url`, so
  // that's tried first, falling back to the fully stringified params for
  // other browser actions (click/type/etc.) that may still embed secrets.
  function extractWebfetchTarget(toolName, params) {
    if (!params || typeof params !== "object") return "";
    if (toolName === "web_search") return typeof params.query === "string" ? params.query : "";
    if (typeof params.url === "string") return params.url;
    if (typeof params.uri === "string") return params.uri;
    return JSON.stringify(params);
  }

  api.on(
    "before_tool_call",
    (event) => {
      const target = extractWebfetchTarget(event.toolName, event.params);
      const result = checkWebfetchGuard({ target, denylistPatterns });
      if (result.decision === "allow") return;
      log("webfetch-domain-guard", result.decision, event.toolName);
      if (result.decision === "deny") return { block: true, blockReason: result.reason };
      return {
        requireApproval: {
          title: "Confirm outbound fetch",
          description: result.reason,
          severity: "warning",
          timeoutMs: 120_000,
          timeoutBehavior: "deny",
        },
      };
    },
    { priority: 85, matcher: ["web_fetch", "web_search", "browser"] },
  );

  // -- e. outbound guard -------------------------------------------------------
  api.on(
    "before_tool_call",
    (event, ctx) => {
      const result = checkOutboundGuard({ toolName: event.toolName, params: event.params, ctx });
      if (result.decision === "allow") return;
      log("outbound-guard", result.decision, event.toolName);
      return {
        requireApproval: {
          title: "Confirm outbound send",
          description: result.reason,
          severity: result.severity || "critical",
          timeoutMs: 120_000,
          timeoutBehavior: "deny",
        },
      };
    },
    { priority: 85, matcher: ["message", "sessions_send"] },
  );

  // message_sending fires for the normal same-channel reply too, and its
  // event shape (to/content/replyToId/threadId/metadata) has no reliable
  // field distinguishing that from a proactive send — see README. Observe
  // and log only; do not cancel.
  api.on("message_sending", (event, ctx) => {
    log("outbound-guard(message_sending)", "observe", `to=${event.to} session=${ctx.sessionKey || "?"}`);
  });

  // -- f. context re-injection --------------------------------------------------
  api.on(
    "before_prompt_build",
    (event, ctx) => {
      const isOrchestrator = ctx.agentId === "main" || ctx.agentId === "orchestrator";
      return { prependSystemContext: buildSystemContext({ caveman, isOrchestrator }) };
    },
    { priority: 70 },
  );

  api.on(
    "agent_turn_prepare",
    (event, ctx) => {
      const notices = drainNotices(ctx.sessionKey);
      const appendContext = buildTurnContext(notices);
      if (!appendContext) return;
      return { appendContext };
    },
    { priority: 70 },
  );

  // -- h. file-read nudge --------------------------------------------------------
  api.on(
    "before_tool_call",
    (event, ctx) => {
      const command = event.params && event.params.command;
      const nudge = checkFileReadNudge(typeof command === "string" ? command : "");
      if (!nudge) return;
      log("bash-file-read-guard", "nudge", command);
      stashNotice(ctx.sessionKey, nudge);
    },
    { priority: 10, matcher: ["exec"] },
  );

  // -- i. session-notification ----------------------------------------------------
  const notify = (title, msg) => {
    if (!notifyCommand) return;
    execFile(notifyCommand, [title, msg], { timeout: 5000 }, () => {});
  };
  api.on("session_end", (event) => {
    log("session-notification", "session_end", event.reason);
    notify("OpenClaw — session ended", `Session ${event.sessionKey || event.sessionId} ended (${event.reason || "unknown"}).`);
  });
  api.on("agent_end", (event, ctx) => {
    log("session-notification", "agent_end", event.success ? "ok" : "error");
    notify("OpenClaw — turn finished", event.success ? "Agent finished this turn." : `Agent turn failed: ${event.error || "unknown error"}`);
  });
}

export default {
  id: "agent-config-guards",
  name: "Agent Config Guards",
  description: "Mirrors the agent-config repo's Claude Code hard-layer hooks (destructive-exec, write-path, write-existing-file, webfetch-domain, outbound, context re-injection, auto-format, comment-checker, file-read nudge, session-notification) as OpenClaw plugin hooks.",
  register,
};

// Exported for scripts/test-openclaw-guards.mjs and for anything that wants
// the wiring logic (not just the pure rules) without spinning up a Gateway.
export { register };
