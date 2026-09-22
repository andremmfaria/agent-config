---
name: gogcli
description: Google CLI (gogcli) patterns — Gmail, Calendar, Drive, Chat, Tasks, Contacts, Sheets, Docs, Meet. Use when working with any Google Workspace service. Auth via stored OAuth token (file keyring). The binary is `gog`, managed by mise (`github:openclaw/gogcli`).
---

## gogcli → `gog` CLI

> Keyring uses encrypted file backend — source before running gog:
> ```bash
> export GOG_KEYRING_BACKEND=file
> export GOG_KEYRING_PASSWORD=$(secret-tool lookup service gogcli key GOG_KEYRING_PASSWORD)
> ```
>
> OAuth client credentials (for re-authorizing accounts):
> ```bash
> export GOOGLE_OAUTH_CLIENT_ID=$(secret-tool lookup service google key GOOGLE_OAUTH_CLIENT_ID)
> export GOOGLE_OAUTH_CLIENT_SECRET=$(secret-tool lookup service google key GOOGLE_OAUTH_CLIENT_SECRET)
> ```

```bash
# Always pass account when multiple Google accounts are configured
gog --account user@example.com <command>

# JSON output for scripting
gog -j <command>

# Dry-run for destructive ops
gog -n <command>

# Auth status
gog auth status
gog auth credentials list
```

---

### Gmail

```bash
# Search messages
gog gmail search "from:boss@company.com is:unread"
gog gmail search "subject:invoice after:2024/01/01" -j

# Read message
gog gmail get <messageId>
gog gmail messages get <messageId> --format full

# Send email
gog gmail send --to "someone@example.com" --subject "Subject" --body "Body"
gog gmail send --to "a@b.com" --cc "c@d.com" --subject "Hi" --body "$(cat body.txt)"

# Archive / trash
gog gmail archive <messageId>
gog gmail trash <messageId>

# Mark read/unread
gog gmail mark-read <messageId>
gog gmail unread <messageId>

# Forward
gog gmail forward --to "other@example.com" <messageId>

# Threads
gog gmail thread list
gog gmail thread get <threadId>

# Labels
gog gmail labels list
```

---

### Calendar

```bash
# List events (default: primary calendar, upcoming)
gog calendar events
gog calendar events --from "2024-01-01" --to "2024-01-31"
gog calendar events -j | jq '.[] | {id, summary, start}'

# Search events
gog calendar search "standup"

# Create event
gog calendar create primary --summary "Meeting" --start "2024-06-01T10:00:00" --end "2024-06-01T11:00:00"

# Update / delete event
gog calendar update primary <eventId> --summary "New Title"
gog calendar delete primary <eventId>

# Free/busy check
gog calendar freebusy --from "2024-06-01T09:00:00" --to "2024-06-01T17:00:00"

# Check conflicts
gog calendar conflicts

# List calendars
gog calendar calendars
```

---

### Drive

```bash
# List / search files
gog drive ls
gog drive search "quarterly report"
gog drive ls --mime application/vnd.google-apps.spreadsheet

# Download / upload
gog drive download <fileId>
gog drive upload ./report.pdf
gog drive upload ./file.csv --parent <folderId>

# File ops
gog drive mkdir "New Folder"
gog drive rename <fileId> "New Name"
gog drive move <fileId> --parent <folderId>
gog drive delete <fileId>

# Sharing
gog drive share <fileId> --role reader --type user --email "someone@example.com"
gog drive permissions <fileId>
```

---

### Chat

```bash
# List spaces (rooms/DMs)
gog chat spaces list
gog chat spaces list -j

# Read messages in a space
gog chat messages list <spaceId>
gog chat messages list <spaceId> --from 1h

# Send message to space
gog chat messages send <spaceId> --text "Hello team"

# DM a user
gog chat dm send <userId> --text "Hey"
```

---

### Tasks

```bash
# List task lists
gog tasks lists list

# List tasks in a list
gog tasks list <tasklistId>
gog tasks list <tasklistId> --show-completed

# Add / complete / delete task
gog tasks add <tasklistId> --title "Do the thing" --due "2024-06-01"
gog tasks done <tasklistId> <taskId>
gog tasks delete <tasklistId> <taskId>
```

---

### Contacts

```bash
# Search contacts
gog contacts search "John"
gog contacts list

# Get contact details
gog contacts get <resourceName>

# Create / update / delete
gog contacts create --given-name "John" --family-name "Doe" --email "john@example.com"
gog contacts update <resourceName> --phone "+1234567890"
gog contacts delete <resourceName>
```

---

### Sheets

```bash
gog sheets --help
```

---

### Auth management

```bash
# Add account (OAuth browser flow)
gog login user@example.com

# Remove account
gog logout user@example.com

# Status
gog auth status
gog whoami
```

---

## Markdown → Google Drive / Docs (pandoc)

Use **pandoc** to convert markdown files before uploading to Google Drive or sending as email bodies.

### Publish markdown as a Word document (DOCX) to Drive

```bash
# Convert markdown to DOCX
pandoc input.md -o /tmp/output.docx

# Upload to Drive root
gog drive upload /tmp/output.docx

# Upload into a specific folder
gog drive upload /tmp/output.docx --parent FOLDER_ID
```

### Convert markdown to PDF and upload

```bash
# Requires a PDF engine (e.g. wkhtmltopdf or weasyprint)
pandoc input.md -o /tmp/output.pdf
gog drive upload /tmp/output.pdf --parent FOLDER_ID
```

### Use markdown content as a Gmail body (plain text)

```bash
# Convert markdown to plain text for email body
BODY=$(pandoc input.md --from=markdown --to=plain)
gog gmail send \
  --to "recipient@example.com" \
  --subject "Report" \
  --body "$BODY"
```

### Convert and send as HTML email

```bash
HTML_BODY=$(pandoc input.md --from=markdown --to=html --standalone)
gog gmail send \
  --to "recipient@example.com" \
  --subject "Report" \
  --body "$HTML_BODY"
```

### Batch convert and upload a directory of markdown files

```bash
for f in ./docs/*.md; do
  name=$(basename "$f" .md)
  pandoc "$f" -o "/tmp/${name}.docx"
  gog drive upload "/tmp/${name}.docx" --parent FOLDER_ID
  echo "Uploaded: ${name}.docx"
done
```
