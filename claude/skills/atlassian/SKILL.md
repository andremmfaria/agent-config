---
name: atlassian
description: Atlassian CLI patterns - Jira via acli (workitems, projects, sprints, boards), Confluence via confpub-cli (primary) or curl+pandoc (fallback). Use when working with Jira tickets or Confluence docs. Auth via $ATLASSIAN_EMAIL, $ATLASSIAN_API_TOKEN, $ATLASSIAN_BASE_URL.
---

## Atlassian → `acli` (Jira) + `confpub` (Confluence)

> Run `check.sh` first to verify acli, confpub, and pandoc are installed and authenticated.

```bash
# Source credentials from keyring before running acli/curl/confpub
export ATLASSIAN_EMAIL=$(secret-tool lookup service atlassian key ATLASSIAN_EMAIL)
export ATLASSIAN_API_TOKEN=$(secret-tool lookup service atlassian key ATLASSIAN_API_TOKEN)
export ATLASSIAN_BASE_URL=$(secret-tool lookup service atlassian key ATLASSIAN_BASE_URL)

# confpub uses its own env var names — map from the above
export CONFPUB_URL="$ATLASSIAN_BASE_URL/wiki"
export CONFPUB_USER="$ATLASSIAN_EMAIL"
export CONFPUB_TOKEN="$ATLASSIAN_API_TOKEN"
```

### First-time auth setup

```bash
echo "$ATLASSIAN_API_TOKEN" | acli jira auth login \
  --site "$(echo $ATLASSIAN_BASE_URL | sed 's|https\?://||')" \
  --email "$ATLASSIAN_EMAIL" \
  --token
```

---

## Jira → `acli`

### Work items — search & view

```bash
# List work items via JQL
acli jira workitem list --jql "project = OPS AND status = 'In Progress'"
acli jira workitem list --jql "assignee = currentUser() ORDER BY created DESC"

# View a work item
acli jira workitem view --key OPS-123
```

### Work items — create & edit

```bash
# Create
acli jira workitem create --summary "Fix login bug" --project OPS --type Bug
acli jira workitem create --summary "New task" --project OPS --type Task \
  --assignee "user@example.com" --label "backend,urgent"

# Edit
acli jira workitem edit --key OPS-123 --summary "Updated summary"
acli jira workitem edit --jql "project = OPS AND status = Open" --assignee "user@example.com"
```

### Work items — transition

```bash
acli jira workitem transition --key OPS-123 --status "In Progress"
acli jira workitem transition --key OPS-123 --status "Done"
acli jira workitem transition --jql "project = OPS AND fixVersion = v1.0" --status "Done" --yes
```

### Work items — comments

```bash
# Plain-text comment (markdown will NOT render — posts literally)
acli jira workitem comment create --key OPS-123 --body "Plain text comment"
acli jira workitem comment list   --key OPS-123 --json
acli jira workitem comment update --key OPS-123 --id 10001 --body "Updated text"
```

#### Comment with rendered formatting (markdown → ADF)

Jira Cloud comments/descriptions are **ADF** (Atlassian Document Format), not markdown.
`--body`/`--body-file` post plain text, so `##`, `| tables |`, and `**bold**` show literally.
Convert markdown to ADF first, then post via REST (create) or `--body-adf` (update only).

**Primary: official Node converter** — uses Atlassian's own
`@atlaskit/editor-markdown-transformer` + `@atlaskit/editor-json-transformer`
(installed in `~/.claude/skills/atlassian/node_modules`).

```bash
# 1. Convert markdown -> ADF JSON (official Atlaskit pipeline)
node ~/.claude/skills/atlassian/md-to-adf.js doc.md /tmp/comment.adf.json

# 2. Validate it parses
python3 -m json.tool /tmp/comment.adf.json > /dev/null

# 3a. Create a rendered comment — `comment create` has NO --body-adf (acli 1.3.x), use REST
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64 -w0)
jq -n --slurpfile b /tmp/comment.adf.json '{body:$b[0]}' > /tmp/payload.json
curl -s -X POST -H "Authorization: Basic $AUTH" -H "Content-Type: application/json" \
  "$ATLASSIAN_BASE_URL/rest/api/3/issue/OPS-123/comment" -d @/tmp/payload.json | jq '.id'

# 3b. …or update an existing one (acli supports --body-adf here; REST PUT to .../comment/ID works too)
acli jira workitem comment update --key OPS-123 --id 10001 --body-adf /tmp/comment.adf.json

# 4. Verify it stored as structured ADF — use REST (comment list returns a string, not ADF):
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64 -w0)
curl -s -H "Authorization: Basic $AUTH" -H "Accept: application/json" \
  "$ATLASSIAN_BASE_URL/rest/api/3/issue/OPS-123/comment/10001" | jq '.body.type'
# should print "doc"
```

> **Fallback (zero-dependency):** if Node or `node_modules` are unavailable, use
> `python3 ~/.claude/skills/atlassian/md-to-adf.py doc.md /tmp/comment.adf.json`
> (stdlib only; handles headings, bold/inline-code, bullet lists, blockquotes, GFM tables, horizontal rules).

#### ADF gotchas

- **Links with code-span labels are silently dropped**: `` [`text`](url) `` converts to code-marked
  text with NO link mark. Use plain labels — `[text](url)`. After converting a doc that should
  contain links, verify before posting: `grep -c '"type": *"link"' comment.adf.json` (or
  `python3 -c "import json; assert 'link' in json.dumps(json.load(open('comment.adf.json')))"`).
- **`comment create` has no `--body-adf`** (only `comment update` does) — see step 3a above for the REST POST.
- **Bare URLs are NOT autolinked** by the converter: `https://x/y` stays plain text (no link mark).
  Always write `[label](url)`. Verify with `jq '[.. | objects | select(.type=="link") | .attrs.href]'`.
- **Appending to an existing comment**: fetch its ADF via REST, `extend` the `body.content` array
  with the new nodes, PUT the whole body back — never regenerate the full comment from scratch
  unless you hold the complete source.

### Projects, boards, sprints

```bash
acli jira project list
acli jira board list
acli jira sprint list --board BOARD_ID
```

### Dashboards & filters

```bash
acli jira dashboard list
acli jira filter list
```

---

## Confluence → `curl` (acli does not support Confluence)

```bash
AUTH=$(echo -n "$ATLASSIAN_EMAIL:$ATLASSIAN_API_TOKEN" | base64 -w0)
# -H "Authorization: Basic $AUTH"
```

### Search pages

```bash
curl -s -H "Authorization: Basic $AUTH" -H "Accept: application/json" \
  "$ATLASSIAN_BASE_URL/wiki/rest/api/content/search?cql=space%3DOP%20AND%20title~%22meeting%22"
```

### Get page content

```bash
curl -s -H "Authorization: Basic $AUTH" -H "Accept: application/json" \
  "$ATLASSIAN_BASE_URL/wiki/rest/api/content/PAGE_ID?expand=body.storage"
```

### Create page (manual HTML body)

```bash
curl -s -X POST \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  "$ATLASSIAN_BASE_URL/wiki/rest/api/content" \
  -d '{
    "type": "page",
    "title": "Page Title",
    "space": {"key": "SPACE_KEY"},
    "ancestors": [{"id": "PARENT_PAGE_ID"}],
    "body": {
      "storage": {
        "value": "<p>Content here</p>",
        "representation": "storage"
      }
    }
  }'
```

### Update page (increment version)

```bash
# Get current version first
VERSION=$(curl -s -H "Authorization: Basic $AUTH" \
  "$ATLASSIAN_BASE_URL/wiki/rest/api/content/PAGE_ID" | jq '.version.number')

curl -s -X PUT \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  "$ATLASSIAN_BASE_URL/wiki/rest/api/content/PAGE_ID" \
  -d "{
    \"type\": \"page\",
    \"title\": \"Page Title\",
    \"version\": {\"number\": $((VERSION + 1))},
    \"body\": {
      \"storage\": {
        \"value\": \"<p>Updated content</p>\",
        \"representation\": \"storage\"
      }
    }
  }"
```

---

## Markdown → Confluence (`confpub` — primary)

**`confpub-cli`** is the primary tool. Handles code blocks as native Confluence macros, Info/Warning/Tip panels, task lists, tables, footnotes, and more — no post-processing needed.

### Publish a single markdown file

```bash
# Creates or updates page (idempotent via lockfile)
confpub page publish doc.md --space ENG --parent "Andre Notes"

# Dry-run first (safe preview)
confpub page publish doc.md --space ENG --parent "Andre Notes" --dry-run
```

### Title and parent gotchas

There is NO `--parent-id` — parent is by **title only** (`--parent "Guides"`). `--page-id` exists but targets the page to update, not the parent.

Default title = filename stem, title-cased — this mangles casing (`via NetBird` → `Via Netbird`). Always pass an explicit title:

```bash
confpub page publish accessing-x-via-netbird.md --space ENG --parent "Guides" \
  --title "Accessing X via NetBird"
# or derive from the doc's first H1:
confpub page publish doc.md --space ENG --parent "Guides" --title-from-h1
```

### Publish multiple files

```bash
# Sequentially
for f in doc1.md doc2.md doc3.md; do
  confpub page publish "$f" --space ENG --parent "Andre Notes"
done
```

### Publish a documentation tree (manifest)

```yaml
# confpub.yaml
schema_version: "1.0"
space: ENG
parent: "Andre Notes"
pages:
  - title: "TA Migration Plan"
    file: ta-migration-plan.md
  - title: "SCP Architecture"
    file: waratek-scp-architecture.md
```

```bash
confpub plan create  --manifest confpub.yaml          # plan (no writes)
confpub plan apply   --plan confpub-plan.json          # apply
confpub plan apply   --plan confpub-plan.json --dry-run  # preview
```

### Pull a Confluence page to markdown

```bash
confpub page pull --space ENG --title "My Page" --output ./docs/
confpub page pull --page-id 4616126465 --recursive --output ./docs/
```

### Search and inspect

```bash
confpub page list --space ENG
confpub search --space ENG --cql 'title ~ "migration"'
confpub page inspect --space ENG --title "My Page"
confpub auth inspect   # verify credentials
```

### Markdown features confpub handles natively

| Markdown | Confluence output |
|---|---|
| ` ```bash ` fenced block | `<ac:structured-macro ac:name="code">` with language |
| `> [!NOTE]` | Info macro |
| `> [!WARNING]` | Warning macro |
| `> [!TIP]` | Tip macro |
| `- [ ]` / `- [x]` | Task list macro |
| `{toc}` | Table of Contents macro |
| `{jira:PROJ-123}` | Jira issue link |
| `::: panel Title` | Panel macro |
| `::: expand Title` | Expand/collapse macro |

---

## Markdown → Confluence (pandoc — fallback)

Use pandoc + curl **only** when confpub is unavailable or fails.

> **Limitation**: pandoc produces plain `<pre><code>` blocks — no styled Confluence code macros unless you post-process.

### Convert and create page from a markdown file

```bash
# 1. Convert markdown to HTML
MD_HTML=$(pandoc "$MD_FILE" --from=markdown --to=html)

# 2. Build JSON payload (jq handles escaping)
BODY=$(jq -n \
  --arg title  "$TITLE" \
  --arg space  "$SPACE_KEY" \
  --arg parent "$PARENT_ID" \
  --arg html   "$MD_HTML" \
  '{
    type: "page",
    title: $title,
    space: {key: $space},
    ancestors: [{id: $parent}],
    body: {storage: {value: $html, representation: "storage"}}
  }')

# 3. POST to Confluence
curl -s -X POST \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  "$ATLASSIAN_BASE_URL/wiki/rest/api/content" \
  -d "$BODY" | jq '{id: .id, url: ._links.webui}'
```

### Convert and update existing page from a markdown file

```bash
MD_HTML=$(pandoc "$MD_FILE" --from=markdown --to=html)

VERSION=$(curl -s -H "Authorization: Basic $AUTH" \
  "$ATLASSIAN_BASE_URL/wiki/rest/api/content/$PAGE_ID" | jq '.version.number')

BODY=$(jq -n \
  --arg title "$TITLE" \
  --argjson ver "$((VERSION + 1))" \
  --arg html  "$MD_HTML" \
  '{
    type: "page",
    title: $title,
    version: {number: $ver},
    body: {storage: {value: $html, representation: "storage"}}
  }')

curl -s -X PUT \
  -H "Authorization: Basic $AUTH" \
  -H "Content-Type: application/json" \
  "$ATLASSIAN_BASE_URL/wiki/rest/api/content/$PAGE_ID" \
  -d "$BODY" | jq '{id: .id, url: ._links.webui}'
```

### Optional: post-process for code macros (pandoc fallback only)

```bash
# Wrap <pre><code> blocks in Confluence code macros
MD_HTML=$(pandoc "$MD_FILE" --from=markdown --to=html | python3 -c "
import re, sys
html = sys.stdin.read()
def repl(m):
    code = m.group(1).replace('&amp;','&').replace('&lt;','<').replace('&gt;','>')
    return '<ac:structured-macro ac:name=\"code\" ac:schema-version=\"1\"><ac:plain-text-body><![CDATA[' + code + ']]></ac:plain-text-body></ac:structured-macro>'
print(re.sub(r'<pre><code[^>]*>(.*?)</code></pre>', repl, html, flags=re.DOTALL))
")
