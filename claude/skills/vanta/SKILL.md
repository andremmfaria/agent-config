---
name: vanta
description: Vanta REST API patterns via curl with OAuth2 - list controls, failing tests, critical vulnerabilities. Use when working with Vanta compliance monitoring. Auth via $VANTA_CLIENT_ID and $VANTA_CLIENT_SECRET.
---

## Vanta → `curl` + OAuth 2.0

> Run `check.sh` first to verify curl/python3 are installed, env vars are set, and OAuth works.

```bash
# Source credentials from keyring before running curl
export VANTA_BASE=$(secret-tool lookup service vanta key VANTA_BASE)
export VANTA_CLIENT_ID=$(secret-tool lookup service vanta key VANTA_CLIENT_ID)
export VANTA_CLIENT_SECRET=$(secret-tool lookup service vanta key VANTA_CLIENT_SECRET)
export VANTA_CLIENT_REGION=$(secret-tool lookup service vanta key VANTA_CLIENT_REGION)
```

### Get token (run first, token expires — re-run as needed)

```bash
VANTA_TOKEN=$(curl -s -L -X POST "$VANTA_BASE/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials&client_id=$VANTA_CLIENT_ID&client_secret=$VANTA_CLIENT_SECRET&scope=vanta-api.all:read" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['access_token'])")
```

### Query

```bash
# Controls
curl -s -L -H "Authorization: Bearer $VANTA_TOKEN" "$VANTA_BASE/v1/controls"

# Failing tests
curl -s -L -H "Authorization: Bearer $VANTA_TOKEN" "$VANTA_BASE/v1/tests?status=NEEDS_ATTENTION"

# Critical vulnerabilities
curl -s -L -H "Authorization: Bearer $VANTA_TOKEN" "$VANTA_BASE/v1/vulnerabilities?severity=CRITICAL"
```
