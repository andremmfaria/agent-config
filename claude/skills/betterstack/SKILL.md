---
name: betterstack
description: BetterStack REST API patterns via curl - monitors, incidents (list/acknowledge/resolve), on-calls, telemetry sources. Use when working with BetterStack uptime or incident management. Auth via $BETTERSTACK_TOKEN.
---

## BetterStack → `curl` + REST API

> Run `check.sh` first to verify curl is installed and env vars + token are valid.

```bash
# Source credentials from keyring before running curl
export BETTERSTACK_TOKEN=$(secret-tool lookup service betterstack key BETTERSTACK_TOKEN)
export BETTERSTACK_UPTIME=$(secret-tool lookup service betterstack key BETTERSTACK_UPTIME)
export BETTERSTACK_TELEMETRY=$(secret-tool lookup service betterstack key BETTERSTACK_TELEMETRY)
# -H "Authorization: Bearer $BETTERSTACK_TOKEN"
```

### Monitors

```bash
curl -s -H "Authorization: Bearer $BETTERSTACK_TOKEN" "$BETTERSTACK_UPTIME/monitors"
```

### Incidents

```bash
# List active incidents
curl -s -H "Authorization: Bearer $BETTERSTACK_TOKEN" "$BETTERSTACK_UPTIME/incidents?resolved=false"

# Acknowledge
curl -s -X POST -H "Authorization: Bearer $BETTERSTACK_TOKEN" \
  "$BETTERSTACK_UPTIME/incidents/ID/acknowledge"

# Resolve
curl -s -X POST -H "Authorization: Bearer $BETTERSTACK_TOKEN" \
  "$BETTERSTACK_UPTIME/incidents/ID/resolve"
```

### On-calls

```bash
curl -s -H "Authorization: Bearer $BETTERSTACK_TOKEN" "$BETTERSTACK_UPTIME/on-calls"
```

### Telemetry sources

```bash
curl -s -H "Authorization: Bearer $BETTERSTACK_TOKEN" "$BETTERSTACK_TELEMETRY/sources"
```
