---
name: web-access
description: Three-layer escalation for fetching web content when a plain fetch is blocked, empty, or shows a challenge page (HTTP 403/429, bot-detection interstitial, JS-only skeleton body, Cloudflare/Akamai challenge). Use when WebFetch fails on a real page the user asked to read, or the user explicitly asks to read a page WebFetch could not retrieve. Not for a 404 or a genuinely missing page.
---

## Web access

Fetching a page has three layers, cheapest and most common first. Escalate only when the current layer genuinely fails, not preemptively. Each layer below states exactly what counts as a failure worth escalating for.

### Layer 1: WebFetch / WebSearch (default)

Always try this first. It costs nothing extra and covers the overwhelming majority of pages.

Escalate past Layer 1 only on a real failure:

- HTTP 403 or 429
- a bot-detection interstitial (Cloudflare, Akamai, PerimeterX, DataDome, and similar)
- a JS-only page that returns an empty or skeleton body (client-rendered content never lands in the fetched HTML)
- a challenge page served in place of content

A 404 or a page that is genuinely missing is not a reason to escalate. Report it as missing.

### Layer 2: `playwright-cli`

Installed at `~/.claude/skills/playwright-cli`. Use it when the page needs JavaScript rendering, a real browser context, a screenshot, or PDF capture, and Layer 1 hit one of the failures above.

Invoke it via the `playwright-cli` skill rather than duplicating its documentation here: load that skill for the full command surface.

### Layer 3: Fortress

Last resort. Reach for this only when a page actively blocks automation and both Layer 1 and Layer 2 have genuinely failed against it (Layer 2 still gets the challenge, a 403, or a bot-check screen).

Fortress is a stealth Chromium engine (BSD 3-Clause, PyPI package `tilion-fortress`, repo `github.com/tiliondev/fortress`). It corrects the browser fingerprint inside Chromium's C++ rather than patching it from JavaScript, so fingerprinting pages see what looks like a stock Chrome install. Verified locally: it presents as `Chrome/149.0.7827.232` on Windows.

Installed on this machine via `uv tool install tilion-fortress`. Drive it through the CLI, then attach `playwright-cli` to its CDP endpoint:

```bash
tilion-fortress --port 9222 &          # add --no-headless to watch it
playwright-cli attach --cdp=http://localhost:9222
```

Stop it when finished, it is a full browser process.

Use the CLI, not the Python API. `from tilion_fortress import Fortress` does not work here because `uv tool` installs into an isolated environment that the system `python3` cannot import from. The CLI is the supported path on this machine.

Fortress exists to reach public documentation, vendor status pages, and reference material that block automated clients. It is not for defeating access controls, scraping at volume, or evading rate limits.

### Known upstream bug

The release tarball extracts to `tillion-fortress/tillion` (double L) while the Python loader looks for `tilion-fortress/tilion` (single L), so a fresh install fails with `bundle extracted but launcher missing`. Worked around with symlinks under `~/.cache/tilion-fortress/<version>/linux-x64/`. A version bump that downloads a new bundle will reintroduce this, and `check.sh` detects it and prints the fix.
