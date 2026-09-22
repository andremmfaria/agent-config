---
name: slack
description: Slack Web API patterns via curl - read/write messages in any channel or DM, threads, search, list conversations, user profiles, reactions, file uploads. Use when working with Slack messages or channels. Auth via $SLACK_USER_TOKEN (xoxp, acts AS the user).
---

## Slack → `curl` + Web API

> Run `check.sh` first to verify curl is installed and the token is valid.
> User-token (xoxp) design: every call acts AS André — messages post under his name/avatar, access mirrors his channel membership. No bot, no channel invites needed.

```bash
# Source credentials from keyring before running curl
export SLACK_USER_TOKEN=$(secret-tool lookup service slack key SLACK_USER_TOKEN)
# -H "Authorization: Bearer $SLACK_USER_TOKEN"
```

Base URL: `https://slack.com/api/METHOD`. GET with query params or POST with JSON (`Content-Type: application/json; charset=utf-8`).

**HTTP 200 does NOT mean success** — Slack always returns 200; check `"ok": true` in the body. On `"ok": false` read the `error` field (`channel_not_found`, `not_in_channel`, `missing_scope`, `ratelimited`).

Pagination: cursor-based — pass `limit` (max 200 for conversations.\*, 1000 for users.list), follow `response_metadata.next_cursor` until empty. On HTTP 429 honor the `Retry-After` header.

Message identity: a message's `ts` (e.g. `1722180000.123456`) is its ID within a channel. Threads: reply with `thread_ts` = parent's `ts`.

### Resolve channel name → ID

Most methods need channel IDs (`C…` public, `G…` private, `D…` DM). Resolve once:

```bash
curl -s -H "Authorization: Bearer $SLACK_USER_TOKEN" \
  "https://slack.com/api/conversations.list?types=public_channel,private_channel&limit=200" \
  | jq -r '.channels[] | "\(.id)\t\(.name)"'
```

### List conversations (channels, DMs, group DMs)

```bash
# All conversation types André is in (im = DMs, mpim = group DMs)
curl -s -H "Authorization: Bearer $SLACK_USER_TOKEN" \
  "https://slack.com/api/conversations.list?types=public_channel,private_channel,im,mpim&exclude_archived=true&limit=200"

# Channel metadata (topic, purpose, member count)
curl -s -H "Authorization: Bearer $SLACK_USER_TOKEN" \
  "https://slack.com/api/conversations.info?channel=$CHANNEL_ID"

# Members of a channel
curl -s -H "Authorization: Bearer $SLACK_USER_TOKEN" \
  "https://slack.com/api/conversations.members?channel=$CHANNEL_ID&limit=200"
```

### Read messages

```bash
# Channel history (newest first); oldest/latest take epoch ts to bound the window
curl -s -H "Authorization: Bearer $SLACK_USER_TOKEN" \
  "https://slack.com/api/conversations.history?channel=$CHANNEL_ID&limit=100"

# Thread replies (parent ts required)
curl -s -H "Authorization: Bearer $SLACK_USER_TOKEN" \
  "https://slack.com/api/conversations.replies?channel=$CHANNEL_ID&ts=1722180000.123456"
```

> History requires membership. For a public channel André isn't in, join first (same as clicking Join in the UI):
> ```bash
> curl -s -X POST -H "Authorization: Bearer $SLACK_USER_TOKEN" \
>   -H "Content-Type: application/json; charset=utf-8" \
>   -d '{"channel":"$CHANNEL_ID"}' "https://slack.com/api/conversations.join"
> ```

### Write messages — posts AS André, confirm before sending

> Anything posted is indistinguishable from André typing it. Always show the exact text + target channel and get explicit confirmation before chat.postMessage to any shared channel or DM.

```bash
# Post message
curl -s -X POST -H "Authorization: Bearer $SLACK_USER_TOKEN" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d '{"channel":"$CHANNEL_ID","text":"message text"}' \
  "https://slack.com/api/chat.postMessage"

# Reply in thread (add reply_broadcast:true to also show in channel)
curl -s -X POST -H "Authorization: Bearer $SLACK_USER_TOKEN" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d '{"channel":"$CHANNEL_ID","thread_ts":"1722180000.123456","text":"reply"}' \
  "https://slack.com/api/chat.postMessage"

# Edit own message
curl -s -X POST -H "Authorization: Bearer $SLACK_USER_TOKEN" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d '{"channel":"$CHANNEL_ID","ts":"1722180000.123456","text":"edited text"}' \
  "https://slack.com/api/chat.update"

# Delete own message
curl -s -X POST -H "Authorization: Bearer $SLACK_USER_TOKEN" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d '{"channel":"$CHANNEL_ID","ts":"1722180000.123456"}' \
  "https://slack.com/api/chat.delete"
```

### DMs

```bash
# Open (or fetch existing) DM with a user — returns channel.id (D…), then post/read as usual
curl -s -X POST -H "Authorization: Bearer $SLACK_USER_TOKEN" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d '{"users":"U0123456789"}' "https://slack.com/api/conversations.open"

# Group DM: comma-separate user IDs in "users"
```

### Search

```bash
# Full workspace search, Slack query syntax (from:@user, in:#channel, before:/after:, "exact phrase")
curl -s -H "Authorization: Bearer $SLACK_USER_TOKEN" \
  --get --data-urlencode 'query=deploy failure in:#ops after:2026-07-01' \
  "https://slack.com/api/search.messages?count=20"
```

### Users / profiles

```bash
# All users (id, name, real_name, deleted flag)
curl -s -H "Authorization: Bearer $SLACK_USER_TOKEN" \
  "https://slack.com/api/users.list?limit=200"

# Single user
curl -s -H "Authorization: Bearer $SLACK_USER_TOKEN" \
  "https://slack.com/api/users.info?user=U0123456789"

# Profile fields (title, email, phone, custom fields)
curl -s -H "Authorization: Bearer $SLACK_USER_TOKEN" \
  "https://slack.com/api/users.profile.get?user=U0123456789"

# ID by email
curl -s -H "Authorization: Bearer $SLACK_USER_TOKEN" \
  "https://slack.com/api/users.lookupByEmail?email=someone@waratek.com"
```

### Reactions

```bash
# Add (name = emoji without colons)
curl -s -X POST -H "Authorization: Bearer $SLACK_USER_TOKEN" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d '{"channel":"$CHANNEL_ID","timestamp":"1722180000.123456","name":"white_check_mark"}' \
  "https://slack.com/api/reactions.add"

# List reactions on a message
curl -s -H "Authorization: Bearer $SLACK_USER_TOKEN" \
  "https://slack.com/api/reactions.get?channel=$CHANNEL_ID&timestamp=1722180000.123456"
```

### File upload — two-step external flow ONLY

> `files.upload` is dead (removed 2025-03-11). Never use it.

```bash
# 1. Get upload URL (length = exact byte count)
resp=$(curl -s -H "Authorization: Bearer $SLACK_USER_TOKEN" \
  --get --data-urlencode "filename=report.txt" \
  --data-urlencode "length=$(stat -c%s report.txt)" \
  "https://slack.com/api/files.getUploadURLExternal")
upload_url=$(echo "$resp" | jq -r .upload_url); file_id=$(echo "$resp" | jq -r .file_id)

# 2. POST the bytes to the returned URL
curl -s -X POST "$upload_url" --data-binary @report.txt

# 3. Finalize + share to channel
curl -s -X POST -H "Authorization: Bearer $SLACK_USER_TOKEN" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d "{\"files\":[{\"id\":\"$file_id\",\"title\":\"report.txt\"}],\"channel_id\":\"$CHANNEL_ID\"}" \
  "https://slack.com/api/files.completeUploadExternal"
```
