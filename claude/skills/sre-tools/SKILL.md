---
name: sre-tools
description: SRE/diagnostic tooling for AWS infrastructure. Spawn a temporary, SSM-Exec-enabled diagnostic Fargate container on the same cluster/network/roles as a target ECS service to run live diagnostics (e.g. psql against a private RDS) without touching the running app. Use when you need a throwaway shell inside a VPC to reach private resources, debug an ECS service's environment, or query a private database.
---

## SRE Tools

Diagnostic helpers for operating AWS infrastructure. Each tool is self-contained — read its `--help` for the full surface.

### `ecs-diag.sh` — temporary SSM-enabled diagnostic container

> Run `check.sh` first to verify aws CLI, session-manager-plugin, and python3 are available.

Spawns a throwaway Fargate task on a target ECS cluster, cloning a real service's network config (subnets, security groups) and IAM roles so the container lands inside the same VPC and can reach private resources (RDS, internal endpoints). ECS Exec is enabled, so you get an interactive `/bin/sh`. It never touches the target service or its tasks — it only creates and tears down its own task.

```bash
ecs-diag.sh spawn    [config...]     # register task-def + run-task w/ exec, wait until exec agent RUNNING, save state
ecs-diag.sh session  --cluster NAME  # interactive shell (aliases: shell, exec); pass `-- <cmd>` for one-off
ecs-diag.sh status   --cluster NAME  # show stored task lastStatus + exec-agent status
ecs-diag.sh teardown --cluster NAME  # stop task, remove state (aliases: down, stop; --deregister also removes task-def rev)
ecs-diag.sh --help
```

**Config** — flags (each has an `ECS_DIAG_*` env fallback):
`--cluster · --subnets · --security-groups · --task-role · --execution-role · --region · --profile · --image · --cpu · --mem · --task-family · --env KEY=VALUE (repeatable)`

**Reuse across apps — `--from-service <name>`:** auto-discovers `subnets`, `security-groups`, `assignPublicIp` from the service's `networkConfiguration` and `executionRole`/`taskRole` from its task definition. Explicit flags always override discovered values. Point it at any service to clone its network + roles in one flag.

Required after resolution: `cluster`, `subnets`, `security-groups`, `execution-role`, `task-role` (supply directly or via `--from-service`).

> ⚠️ **ECS Exec needs SSM perms on the TASK ROLE.** The `--task-role` must allow `ssmmessages:CreateControlChannel/CreateDataChannel/OpenControlChannel/OpenDataChannel` or `session` fails. Verify before relying on it.

> ⚠️ `spawn` creates a real Fargate task in the target account (billable until `teardown`). It does not modify the target service.

#### Example — portal-prod RDS diagnosis (acct 253924915879)

```bash
# 1. Spawn a postgres-client container cloned from the portal-prod service network/roles
ecs-diag.sh spawn --profile AdminPortalProd --region us-east-1 \
  --cluster portal-prod --from-service portal-prod \
  --env PGHOST=portal-rds-prod.c4lg626ysxdk.us-east-1.rds.amazonaws.com \
  --env PGPORT=5432 --env PGDATABASE=portal

# 2. Fetch DB creds LOCALLY (host can't reach the private RDS; creds only):
aws secretsmanager get-secret-value \
  --secret-id 'arn:aws:secretsmanager:us-east-1:253924915879:secret:rds!db-5ea86be4-c82e-499d-9a40-5068de81dd37-iCXh0b' \
  --query SecretString --profile AdminPortalProd --region us-east-1

# 3. Open a shell and run psql (read-only diagnostics, e.g. per-schema access_key check):
ecs-diag.sh session --cluster portal-prod --profile AdminPortalProd --region us-east-1
#   in-container:  PGPASSWORD=<password> psql -U <username> -h "$PGHOST" -d portal

# 4. Always tear down when done
ecs-diag.sh teardown --cluster portal-prod --profile AdminPortalProd --region us-east-1
```

Default image is `public.ecr.aws/docker/library/postgres:16-alpine` (ships `psql`; shell is `/bin/sh`). Override with `--image` for other diagnostics (use `-- /bin/bash` on Debian-based images).
