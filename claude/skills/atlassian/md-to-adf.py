#!/usr/bin/env python3
"""
Convert Markdown to Atlassian Document Format (ADF) JSON.

Jira Cloud comments and descriptions are ADF, NOT markdown — `acli ... --body`
posts plain text, so raw markdown (##, | tables |, **bold**) renders literally.
Convert first, then post with `acli ... --body-adf <file.json>`.

Usage:
  python3 md-to-adf.py INPUT.md OUTPUT.json

Supported constructs (the common subset; extend if you need more):
  - Headings H1-H3
  - Paragraphs with **bold** and `inline code`
  - Bullet lists (-, *)
  - Blockquotes (>)
  - GFM tables (first row -> tableHeader)
  - Horizontal rules (---)

Standard library only — no pip installs.
"""

import re
import json
import sys


def parse_inline(text: str) -> list:
    """Parse inline markdown (**bold**, `code`, plain text) into ADF inline nodes."""
    nodes = []
    pattern = re.compile(r'(\*\*(.+?)\*\*|`(.+?)`)')
    pos = 0
    for m in pattern.finditer(text):
        start, end = m.start(), m.end()
        if pos < start:
            nodes.append({"type": "text", "text": text[pos:start]})
        if m.group(2) is not None:
            nodes.append({"type": "text", "text": m.group(2), "marks": [{"type": "strong"}]})
        else:
            nodes.append({"type": "text", "text": m.group(3), "marks": [{"type": "code"}]})
        pos = end
    if pos < len(text):
        nodes.append({"type": "text", "text": text[pos:]})
    return nodes if nodes else [{"type": "text", "text": text}]


def make_paragraph(text: str) -> dict:
    return {"type": "paragraph", "content": parse_inline(text)}


def parse_table(lines: list) -> dict:
    """Parse GFM table lines into an ADF table node (first row -> tableHeader)."""
    rows = []
    for i, line in enumerate(lines):
        stripped = line.strip().strip('|').strip()
        if re.match(r'^[\s\|\-:]+$', stripped):  # separator row
            continue
        cells = [c.strip() for c in re.split(r'\|', line.strip().strip('|'))]
        cell_type = "tableHeader" if i == 0 else "tableCell"
        adf_cells = [
            {"type": cell_type, "attrs": {}, "content": [make_paragraph(cell)]}
            for cell in cells
        ]
        rows.append({"type": "tableRow", "content": adf_cells})
    return {
        "type": "table",
        "attrs": {"isNumberColumnEnabled": False, "layout": "default"},
        "content": rows,
    }


def convert(md_text: str) -> dict:
    lines = md_text.split('\n')
    content = []
    i = 0

    while i < len(lines):
        line = lines[i]

        if re.match(r'^---+\s*$', line):
            content.append({"type": "rule"})
            i += 1
            continue

        m = re.match(r'^(#{1,3})\s+(.*)', line)
        if m:
            content.append({
                "type": "heading",
                "attrs": {"level": len(m.group(1))},
                "content": parse_inline(m.group(2)),
            })
            i += 1
            continue

        if '|' in line and line.strip().startswith('|'):
            table_lines = []
            while i < len(lines) and '|' in lines[i] and lines[i].strip().startswith('|'):
                table_lines.append(lines[i])
                i += 1
            content.append(parse_table(table_lines))
            continue

        if re.match(r'^[-*]\s+', line):
            items = []
            while i < len(lines) and re.match(r'^[-*]\s+', lines[i]):
                item_text = re.sub(r'^[-*]\s+', '', lines[i])
                items.append({"type": "listItem", "content": [make_paragraph(item_text)]})
                i += 1
            content.append({"type": "bulletList", "content": items})
            continue

        if line.startswith('>'):
            bq_text = re.sub(r'^>\s*', '', line)
            content.append({"type": "blockquote", "content": [make_paragraph(bq_text)]})
            i += 1
            continue

        if line.strip() == '':
            i += 1
            continue

        para_lines = []
        while i < len(lines):
            l = lines[i]
            if (l.strip() == '' or
                    re.match(r'^#{1,3}\s', l) or
                    re.match(r'^---+\s*$', l) or
                    re.match(r'^[-*]\s+', l) or
                    (('|' in l) and l.strip().startswith('|')) or
                    l.startswith('>')):
                break
            para_lines.append(l)
            i += 1
        full_text = ' '.join(para_lines).strip()
        if full_text:
            content.append(make_paragraph(full_text))

    return {"version": 1, "type": "doc", "content": content}


if __name__ == '__main__':
    if len(sys.argv) != 3:
        sys.exit("usage: md-to-adf.py INPUT.md OUTPUT.json")
    with open(sys.argv[1]) as f:
        doc = convert(f.read())
    with open(sys.argv[2], 'w') as f:
        json.dump(doc, f, indent=2, ensure_ascii=False)
    print(f"Wrote ADF to {sys.argv[2]}")
