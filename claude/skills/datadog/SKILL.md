---
name: datadog
description: Datadog CLI patterns via ddogctl - validate auth, search logs, query metrics, search APM spans, list monitors, investigate services. Use when working with Datadog observability. Auth via $DD_API_KEY, $DD_APP_KEY.
---

## Datadog → `ddogctl` CLI

> **MANDATORY**: Export all 3 vars before EVERY `ddogctl` command. Missing any one (especially `DD_SITE`) causes silent failures — wrong region, empty results, or auth errors.

```bash
# ALWAYS run this block before any ddogctl command
export DD_API_KEY=$(secret-tool lookup service datadog key DD_API_KEY)
export DD_APP_KEY=$(secret-tool lookup service datadog key DD_APP_KEY)
export DD_SITE=$(secret-tool lookup service datadog key DD_SITE)
```

> `DD_SITE` controls the region (e.g. `datadoghq.eu`). Without it, ddogctl defaults to `datadoghq.com` (US) and returns empty results even when data exists.

### Monitors

```bash
ddogctl monitor list
ddogctl monitor list --state Alert
ddogctl monitor get MONITOR_ID
ddogctl monitor mute MONITOR_ID
ddogctl monitor unmute MONITOR_ID
```

### Logs

```bash
ddogctl logs search "status:error" --service my-api --from 30m
ddogctl logs search "env:prod service:web" --from 1h
ddogctl logs tail "env:prod" --follow
```

### Metrics

```bash
ddogctl metric query "avg:system.cpu.user{env:prod}" --from 1h
ddogctl metric query "sum:requests.count{service:api}.as_count()" --from 24h
ddogctl metric search "cpu"
```

### APM

```bash
ddogctl apm services
ddogctl apm traces my-service --from 1h
```

### Events

```bash
ddogctl event list --from 1d
ddogctl event post "Deployment" "v2.1.0 deployed to prod"
```

### Hosts

```bash
ddogctl host list
ddogctl host list --filter "env:prod"
ddogctl host info HOSTNAME
```

### Investigation workflows

```bash
ddogctl investigate service my-api --from 1h
ddogctl investigate host web-prod-01 --from 30m
```

### Database Monitoring

```bash
ddogctl dbm slow-queries --service postgres-prod --from 1h
```
