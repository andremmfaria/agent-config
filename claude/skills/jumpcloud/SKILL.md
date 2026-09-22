---
name: jumpcloud
description: JumpCloud REST API patterns via curl - users, systems, groups, policies, SSO applications, Directory Insights events. Use when working with JumpCloud identity/SSO/MDM. Auth via $JUMPCLOUD_API_KEY.
---

## JumpCloud → `curl` + REST API

> Run `check.sh` first to verify curl is installed and the API key is valid.
> No official CLI exists — v1 (`/api`) and v2 (`/api/v2`) REST APIs are the tooling.

```bash
# Source credentials from keyring before running curl
export JUMPCLOUD_API_KEY=$(secret-tool lookup service jumpcloud key JUMPCLOUD_API_KEY)
# -H "x-api-key: $JUMPCLOUD_API_KEY"
```

Base URLs:
- v1: `https://console.jumpcloud.com/api` — systemusers, systems, applications, commands
- v2: `https://console.jumpcloud.com/api/v2` — usergroups, systemgroups, policies, graph/associations
- Directory Insights: `https://api.jumpcloud.com/insights/directory/v1`

Pagination: `?skip=N&limit=100&sort=_id` (sort by `_id` avoids dupes/gaps). On 429/5xx back off and retry; 4xx means fix the request.

### Users

```bash
# List (paginated)
curl -s -H "x-api-key: $JUMPCLOUD_API_KEY" \
  "https://console.jumpcloud.com/api/systemusers?limit=100&sort=_id"

# ID by username
curl -s -H "x-api-key: $JUMPCLOUD_API_KEY" \
  "https://console.jumpcloud.com/api/systemusers?fields=id&filter=username:\$eq:USERNAME"

# Single user
curl -s -H "x-api-key: $JUMPCLOUD_API_KEY" \
  "https://console.jumpcloud.com/api/systemusers/USER_ID"
```

### Systems (devices)

```bash
# List
curl -s -H "x-api-key: $JUMPCLOUD_API_KEY" \
  "https://console.jumpcloud.com/api/systems?limit=100&sort=_id"

# ID by hostname
curl -s -H "x-api-key: $JUMPCLOUD_API_KEY" \
  "https://console.jumpcloud.com/api/systems?fields=id&filter=hostname:\$eq:HOSTNAME"
```

### Groups (v2)

```bash
# User groups
curl -s -H "x-api-key: $JUMPCLOUD_API_KEY" \
  "https://console.jumpcloud.com/api/v2/usergroups?limit=100"

# Group ID by name
curl -s -H "x-api-key: $JUMPCLOUD_API_KEY" \
  "https://console.jumpcloud.com/api/v2/usergroups?fields=id&filter=name:eq:GROUPNAME"

# Members of a user group
curl -s -H "x-api-key: $JUMPCLOUD_API_KEY" \
  "https://console.jumpcloud.com/api/v2/usergroups/GROUP_ID/members"

# System groups
curl -s -H "x-api-key: $JUMPCLOUD_API_KEY" \
  "https://console.jumpcloud.com/api/v2/systemgroups?limit=100"
```

### SSO applications (v1)

```bash
curl -s -H "x-api-key: $JUMPCLOUD_API_KEY" \
  "https://console.jumpcloud.com/api/applications"
```

### Policies (v2)

```bash
curl -s -H "x-api-key: $JUMPCLOUD_API_KEY" \
  "https://console.jumpcloud.com/api/v2/policies?limit=100"
```

### Associations / graph (v2)

```bash
# User groups a user belongs to
curl -s -H "x-api-key: $JUMPCLOUD_API_KEY" \
  "https://console.jumpcloud.com/api/v2/users/USER_ID/memberof"

# Systems bound to a user
curl -s -H "x-api-key: $JUMPCLOUD_API_KEY" \
  "https://console.jumpcloud.com/api/v2/users/USER_ID/systems"
```

### Directory Insights (audit/event logs)

```bash
curl -s -X POST "https://api.jumpcloud.com/insights/directory/v1/events" \
  -H "x-api-key: $JUMPCLOUD_API_KEY" -H "Content-Type: application/json" \
  --data '{"service": ["all"], "start_time": "2026-07-01T00:00:00Z", "limit": 100}'
```
