#!/usr/bin/env python3
"""Validate agent-config repo: referenced paths exist, agent frontmatter is complete.

Usage:
    python3 scripts/validate-config.py

Exits 0 when clean, non-zero on any failure.
"""

import json
import os
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parent.parent

ERRORS: list[str] = []
CHECKS = 0


def fail(msg: str) -> None:
    ERRORS.append(msg)


def check(condition: bool, msg: str) -> None:
    global CHECKS
    CHECKS += 1
    if not condition:
        fail(msg)


# ---------------------------------------------------------------------------
# Frontmatter parser (no PyYAML — line-based scanner)
# ---------------------------------------------------------------------------

def parse_frontmatter(path: Path) -> dict[str, str] | None:
    """Return key→value dict for YAML frontmatter, or None if absent.

    Handles only simple scalar lines (key: value).  Multi-line values and
    block scalars are intentionally out of scope; the convention in this repo
    uses only single-line values for the required keys.
    """
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        fail(f"Cannot read {path.relative_to(REPO_ROOT)}: {exc}")
        return None

    if not lines or lines[0].strip() != "---":
        return None

    fm: dict[str, str] = {}
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if ":" in line:
            key, _, value = line.partition(":")
            fm[key.strip()] = value.strip()
    return fm


# ---------------------------------------------------------------------------
# 1. JSON config path references
# ---------------------------------------------------------------------------

def collect_claude_paths(data: dict) -> list[str]:
    """Return all file paths referenced in claude.json."""
    paths: list[str] = []
    if gi := data.get("global_instruction"):
        paths.append(gi)
    if dos := data.get("default_output_style", {}):
        if p := dos.get("path"):
            paths.append(p)
    for agent in data.get("agents", []):
        if p := agent.get("prompt"):
            paths.append(p)
    return paths


def collect_openclaw_paths(data: dict) -> list[str]:
    """Return all file paths referenced in openclaw.json.

    The schema uses workspace directories + instruction_files lists.  Each
    resolved path is workspace_dir/filename.  optional_private_files are
    intentionally skipped (they may not exist on every machine).
    """
    paths: list[str] = []

    ws = data.get("workspace", {})
    ws_path = ws.get("path", "")
    for fname in ws.get("instruction_files", []):
        paths.append(f"{ws_path}/{fname}")

    for agent in data.get("agents", []):
        agent_ws = agent.get("workspace", "")
        for fname in agent.get("instruction_files", []):
            paths.append(f"{agent_ws}/{fname}")

    return paths


def validate_paths(config_file: str, raw_paths: list[str]) -> None:
    label = config_file
    for raw in raw_paths:
        # Paths in the JSON are relative to the repo root (start with "./")
        rel = raw.lstrip("./")
        abs_path = REPO_ROOT / rel
        check(
            abs_path.exists(),
            f"[{label}] missing referenced path: {raw}",
        )


def validate_json_configs() -> None:
    for fname, collector in [
        ("claude/claude.json", collect_claude_paths),
        ("openclaw/openclaw.json", collect_openclaw_paths),
    ]:
        config_path = REPO_ROOT / fname
        check(config_path.exists(), f"Config file missing: {fname}")
        if not config_path.exists():
            continue

        try:
            data = json.loads(config_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            fail(f"[{fname}] JSON parse error: {exc}")
            continue

        paths = collector(data)
        validate_paths(fname, paths)
        print(f"  {fname}: {len(paths)} path reference(s) checked")


# ---------------------------------------------------------------------------
# 2. Claude agent frontmatter
# ---------------------------------------------------------------------------

# Keys every claude agent .md file must have (non-empty scalar values).
# 'tools' is intentionally omitted: craftsman legitimately has no tools
# restriction and omits the key.
REQUIRED_KEYS = ("name", "description", "model")


def validate_claude_agents() -> None:
    agents_dir = REPO_ROOT / "claude" / "agents"
    md_files = sorted(agents_dir.glob("*.md"))
    check(len(md_files) > 0, "No .md files found under claude/agents/")

    for md in md_files:
        rel = md.relative_to(REPO_ROOT)
        fm = parse_frontmatter(md)
        if fm is None:
            fail(f"[{rel}] no YAML frontmatter found")
            continue
        for key in REQUIRED_KEYS:
            check(
                bool(fm.get(key)),
                f"[{rel}] missing or empty frontmatter key: '{key}'",
            )

    print(f"  claude/agents/: {len(md_files)} file(s) checked")


# ---------------------------------------------------------------------------
# 3. Output-styles frontmatter (same convention as agents)
# ---------------------------------------------------------------------------

def validate_output_styles() -> None:
    styles_dir = REPO_ROOT / "claude" / "output-styles"
    md_files = sorted(styles_dir.glob("*.md"))
    # Output-style files are prose prompts, not agent definitions.  They use a
    # subset of frontmatter (name + description, no model/tools), so we only
    # check that 'name' is present when frontmatter exists.
    OUTPUT_STYLE_KEYS = ("name", "description")
    for md in md_files:
        rel = md.relative_to(REPO_ROOT)
        fm = parse_frontmatter(md)
        if fm is None:
            continue  # No frontmatter — acceptable for pure prose style files
        for key in OUTPUT_STYLE_KEYS:
            check(
                bool(fm.get(key)),
                f"[{rel}] missing or empty frontmatter key: '{key}'",
            )
    if md_files:
        print(f"  claude/output-styles/: {len(md_files)} file(s) checked")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    print("Validating agent-config repo...")
    print()

    print("Path references (JSON configs):")
    validate_json_configs()

    print()
    print("Agent frontmatter (claude/):")
    validate_claude_agents()
    validate_output_styles()

    print()
    print(f"Checks run: {CHECKS}")
    if ERRORS:
        print(f"FAILED — {len(ERRORS)} problem(s):")
        for err in ERRORS:
            print(f"  - {err}")
        return 1

    print("All checks passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
