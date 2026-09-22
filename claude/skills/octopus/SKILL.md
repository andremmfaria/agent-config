---
name: octopus
description: Octopus Deploy CLI patterns - list spaces/projects/releases/deployments, run runbooks, check tasks. Use when working with Octopus Deploy deployments or runbooks. Auth via $OCTOPUS_URL and $OCTOPUS_API_KEY.
---

## OctopusDeploy → `octopus` CLI

> Run `check.sh` first to verify octopus CLI is installed and the connection is valid.

```bash
# Source credentials from keyring before running octopus CLI
export OCTOPUS_URL=$(secret-tool lookup service octopus key OCTOPUS_URL)
export OCTOPUS_API_KEY=$(secret-tool lookup service octopus key OCTOPUS_API_KEY)
# octopus CLI reads OCTOPUS_URL and OCTOPUS_API_KEY automatically
```

### Query

```bash
octopus space list
octopus project list
octopus release list --project PROJECT
octopus deployment list --project PROJECT
octopus task list
```

### Deploy & run

```bash
# Trigger runbook
octopus runbook run --project PROJECT --runbook RUNBOOK --environment ENV

# Raw API fallback
octopus api GET /api/Spaces-1/deployments?take=10
```
