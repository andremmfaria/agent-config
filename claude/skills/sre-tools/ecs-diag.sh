#!/usr/bin/env bash
# ecs-diag.sh — Spawn a throwaway SSM-Exec-enabled diagnostic container on any
# ECS Fargate cluster, in the same network as a target service, without
# touching any production tasks.
#
# All infra config comes from flags (or ECS_DIAG_* env vars) — no
# portal-prod defaults are baked in.  Use --from-service to auto-discover
# network/role config from an existing service.
#
# IMPORTANT — ECS Exec requirement:
#   The task role (--task-role) MUST allow the following ssmmessages actions;
#   otherwise `session` will silently fail:
#     ssmmessages:CreateControlChannel
#     ssmmessages:CreateDataChannel
#     ssmmessages:OpenControlChannel
#     ssmmessages:OpenDataChannel
#   If you use --from-service the discovered task role may already have these.
#   If you supply a custom --task-role, verify the policy is attached first.
#
# ---------------------------------------------------------------------------
# Portal-prod quick reference (--from-service discovers subnets/SGs/roles):
#
#   ecs-diag.sh spawn \
#     --profile AdminPortalProd --region us-east-1 --cluster portal-prod \
#     --from-service portal-prod \
#     --env PGHOST=portal-rds-prod.c4lg626ysxdk.us-east-1.rds.amazonaws.com \
#     --env PGPORT=5432 \
#     --env PGDATABASE=portal
#
#   # Fetch DB creds (run LOCALLY — your machine cannot reach private RDS):
#   aws secretsmanager get-secret-value \
#     --secret-id arn:aws:secretsmanager:us-east-1:253924915879:secret:rds!db-5ea86be4-c82e-499d-9a40-5068de81dd37-iCXh0b \
#     --query SecretString --output text \
#     --profile AdminPortalProd --region us-east-1
#   # Then inside the container:
#   #   PGPASSWORD=<password> psql -U <username> -h $PGHOST -d portal
# ---------------------------------------------------------------------------

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults (only non-infra values have defaults)
# ---------------------------------------------------------------------------
PROFILE="${ECS_DIAG_PROFILE:-}"
REGION="${ECS_DIAG_REGION:-us-east-1}"
CLUSTER="${ECS_DIAG_CLUSTER:-}"

SUBNETS="${ECS_DIAG_SUBNETS:-}"
SECURITY_GROUPS="${ECS_DIAG_SECURITY_GROUPS:-}"
ASSIGN_PUBLIC_IP="DISABLED"

EXECUTION_ROLE="${ECS_DIAG_EXECUTION_ROLE:-}"
TASK_ROLE="${ECS_DIAG_TASK_ROLE:-}"

IMAGE="${ECS_DIAG_IMAGE:-public.ecr.aws/docker/library/postgres:16-alpine}"
CPU="${ECS_DIAG_CPU:-256}"
MEM="${ECS_DIAG_MEM:-512}"

TASK_FAMILY="${ECS_DIAG_TASK_FAMILY:-ecs-diag}"
STATE_DIR="${HOME}/scripts"

FROM_SERVICE=""
# Container env pairs collected from --env KEY=VALUE flags
ENV_PAIRS=()

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
state_file() {
  echo "${STATE_DIR}/.ecs-diag-${CLUSTER}-${TASK_FAMILY}.state"
}

aws_cmd() {
  local args=()
  [[ -n "${PROFILE}" ]] && args+=(--profile "${PROFILE}")
  aws "${args[@]}" --region "${REGION}" "$@"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

# Build a JSON array string from a comma-separated list.
# csv_to_json_array "a,b,c" -> "\"a\",\"b\",\"c\""
csv_to_json_array() {
  local csv="$1"
  echo "${csv}" | tr ',' '\n' | \
    awk '{printf "%s\"%s\"", (NR==1?"":","), $0} END{print ""}'
}

# Build a JSON environment array from ENV_PAIRS.
# Each entry is {"name":"KEY","value":"VALUE"}
build_env_json() {
  local first=true
  echo -n "["
  for pair in "${ENV_PAIRS[@]+"${ENV_PAIRS[@]}"}"; do
    local key="${pair%%=*}"
    local val="${pair#*=}"
    # Escape backslashes and double-quotes in value
    val="${val//\\/\\\\}"
    val="${val//\"/\\\"}"
    if [[ "${first}" == "true" ]]; then
      first=false
    else
      echo -n ","
    fi
    echo -n "{\"name\":\"${key}\",\"value\":\"${val}\"}"
  done
  echo -n "]"
}

usage() {
  cat <<EOF
Usage: ecs-diag.sh [OPTIONS] <subcommand> [args]

Subcommands:
  spawn   | up        Register a new task-def revision and run a throwaway
                      diagnostic container.  Polls until ECS Exec agent is
                      RUNNING, then prints the task ARN.
  session | shell | exec
                      Open an interactive ECS Exec shell into the running
                      diagnostic container.  Args after -- are passed as the
                      container command, e.g.:
                        ecs-diag.sh session -- psql -U myuser
  teardown| down | stop
                      Stop the running diagnostic task, optionally deregister
                      the task-def revision, and remove the state file.
  status              Show the stored task ARN and its current ECS status.

Infra options (flags take precedence; ECS_DIAG_* env vars are fallbacks):
  --profile  PROFILE         AWS profile          [ECS_DIAG_PROFILE]
  --region   REGION          AWS region           [ECS_DIAG_REGION]     (default: us-east-1)
  --cluster  CLUSTER         ECS cluster name     [ECS_DIAG_CLUSTER]    (REQUIRED)
  --subnets  A,B,...         Subnet IDs           [ECS_DIAG_SUBNETS]    (REQUIRED unless --from-service)
  --security-groups A,B,...  Security group IDs   [ECS_DIAG_SECURITY_GROUPS] (REQUIRED unless --from-service)
  --task-role   ARN          Task IAM role ARN    [ECS_DIAG_TASK_ROLE]  (REQUIRED unless --from-service)
  --execution-role ARN       Exec IAM role ARN    [ECS_DIAG_EXECUTION_ROLE] (REQUIRED unless --from-service)
  --task-family NAME         Task def family name [ECS_DIAG_TASK_FAMILY] (default: ecs-diag)
  --image    IMAGE           Container image      [ECS_DIAG_IMAGE]      (default: postgres:16-alpine)
  --cpu      UNITS           Task CPU units       [ECS_DIAG_CPU]        (default: 256)
  --mem      MIB             Task memory MiB      [ECS_DIAG_MEM]        (default: 512)

Discovery:
  --from-service NAME        Auto-derive subnets, security-groups, assignPublicIp,
                             and execution-role (+ task-role if --task-role not given)
                             from the named service's network config and task definition.
                             Requires --cluster, --profile, --region to be set.
                             Explicit flags always override discovered values.

Container environment:
  --env KEY=VALUE            Inject an env var into the diagnostic container.
                             Repeatable.  Pass whatever the target app needs, e.g.:
                               --env PGHOST=db.internal --env PGPORT=5432

Other:
  --deregister               Also deregister the task-def revision on teardown.
  -h | --help                Show this help.

IMPORTANT — ECS Exec permissions:
  The task role MUST allow ssmmessages:CreateControlChannel,
  CreateDataChannel, OpenControlChannel, OpenDataChannel.
  A custom --task-role without these will cause \`session\` to fail.

Portal-prod example (--from-service discovers subnets / SGs / roles):
  ecs-diag.sh spawn \\
    --profile AdminPortalProd --region us-east-1 --cluster portal-prod \\
    --from-service portal-prod \\
    --env PGHOST=portal-rds-prod.c4lg626ysxdk.us-east-1.rds.amazonaws.com \\
    --env PGPORT=5432 \\
    --env PGDATABASE=portal

  # Fetch DB creds (run LOCALLY):
  aws secretsmanager get-secret-value \\
    --secret-id arn:aws:secretsmanager:us-east-1:253924915879:secret:rds!db-5ea86be4-c82e-499d-9a40-5068de81dd37-iCXh0b \\
    --query SecretString --output text \\
    --profile AdminPortalProd --region us-east-1
  # Then inside the container:
  #   PGPASSWORD=<pw> psql -U <user> -h \$PGHOST -d portal
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
SUBCOMMAND=""
SESSION_ARGS=()
DEREGISTER_TASKDEF="false"

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)            usage; exit 0 ;;
      --profile)            PROFILE="$2";          shift 2 ;;
      --region)             REGION="$2";           shift 2 ;;
      --cluster)            CLUSTER="$2";          shift 2 ;;
      --subnets)            SUBNETS="$2";          shift 2 ;;
      --security-groups)    SECURITY_GROUPS="$2";  shift 2 ;;
      --task-role)          TASK_ROLE="$2";        shift 2 ;;
      --execution-role)     EXECUTION_ROLE="$2";   shift 2 ;;
      --task-family)        TASK_FAMILY="$2";      shift 2 ;;
      --image)              IMAGE="$2";            shift 2 ;;
      --cpu)                CPU="$2";              shift 2 ;;
      --mem)                MEM="$2";              shift 2 ;;
      --from-service)       FROM_SERVICE="$2";     shift 2 ;;
      --env)                ENV_PAIRS+=("$2");     shift 2 ;;
      --deregister)         DEREGISTER_TASKDEF="true"; shift ;;
      spawn|up)             SUBCOMMAND="spawn";    shift ;;
      session|shell|exec)   SUBCOMMAND="session";  shift ;;
      teardown|down|stop)   SUBCOMMAND="teardown"; shift ;;
      status)               SUBCOMMAND="status";   shift ;;
      --)                   shift; SESSION_ARGS=("$@"); break ;;
      *)
        if [[ -z "${SUBCOMMAND}" ]]; then
          die "Unknown option or subcommand: $1  (try --help)"
        fi
        SESSION_ARGS+=("$1")
        shift
        ;;
    esac
  done
}

# ---------------------------------------------------------------------------
# --from-service discovery
# ---------------------------------------------------------------------------
resolve_from_service() {
  [[ -z "${FROM_SERVICE}" ]] && return 0

  [[ -z "${CLUSTER}" ]]  && die "--from-service requires --cluster"
  [[ -z "${REGION}" ]]   && die "--from-service requires --region"

  echo "==> Discovering config from service '${FROM_SERVICE}' on cluster '${CLUSTER}' ..."

  local svc_json
  svc_json=$(aws_cmd ecs describe-services \
    --cluster "${CLUSTER}" \
    --services "${FROM_SERVICE}" \
    --query "services[0]" \
    --output json)

  local svc_status
  svc_status=$(echo "${svc_json}" | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get('status','MISSING'))")
  [[ "${svc_status}" == "MISSING" ]] && \
    die "Service '${FROM_SERVICE}' not found on cluster '${CLUSTER}'"

  # Network config
  local discovered_subnets discovered_sgs discovered_public
  discovered_subnets=$(echo "${svc_json}" | python3 -c "
import sys, json
cfg = json.load(sys.stdin).get('networkConfiguration',{}).get('awsvpcConfiguration',{})
print(','.join(cfg.get('subnets',[])))
")
  discovered_sgs=$(echo "${svc_json}" | python3 -c "
import sys, json
cfg = json.load(sys.stdin).get('networkConfiguration',{}).get('awsvpcConfiguration',{})
print(','.join(cfg.get('securityGroups',[])))
")
  discovered_public=$(echo "${svc_json}" | python3 -c "
import sys, json
cfg = json.load(sys.stdin).get('networkConfiguration',{}).get('awsvpcConfiguration',{})
print(cfg.get('assignPublicIp','DISABLED'))
")

  # Task definition for roles
  local taskdef_arn exec_role task_role_discovered
  taskdef_arn=$(echo "${svc_json}" | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get('taskDefinition',''))")

  [[ -z "${taskdef_arn}" ]] && \
    die "Could not determine task definition from service '${FROM_SERVICE}'"

  local td_json
  td_json=$(aws_cmd ecs describe-task-definition \
    --task-definition "${taskdef_arn}" \
    --query "taskDefinition" \
    --output json)

  exec_role=$(echo "${td_json}" | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get('executionRoleArn',''))")
  task_role_discovered=$(echo "${td_json}" | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get('taskRoleArn',''))")

  # Apply discovered values — explicit flags (already set in variables) win
  if [[ -z "${SUBNETS}" ]]; then
    SUBNETS="${discovered_subnets}"
    echo "    subnets (discovered)         : ${SUBNETS}"
  else
    echo "    subnets (explicit override)  : ${SUBNETS}"
  fi

  if [[ -z "${SECURITY_GROUPS}" ]]; then
    SECURITY_GROUPS="${discovered_sgs}"
    echo "    security-groups (discovered) : ${SECURITY_GROUPS}"
  else
    echo "    security-groups (override)   : ${SECURITY_GROUPS}"
  fi

  # assignPublicIp: always take discovered value (no explicit flag for this)
  ASSIGN_PUBLIC_IP="${discovered_public}"
  echo "    assignPublicIp (discovered)  : ${ASSIGN_PUBLIC_IP}"

  if [[ -z "${EXECUTION_ROLE}" ]]; then
    EXECUTION_ROLE="${exec_role}"
    echo "    execution-role (discovered)  : ${EXECUTION_ROLE}"
  else
    echo "    execution-role (override)    : ${EXECUTION_ROLE}"
  fi

  if [[ -z "${TASK_ROLE}" ]]; then
    TASK_ROLE="${task_role_discovered}"
    echo "    task-role (discovered)       : ${TASK_ROLE}"
  else
    echo "    task-role (override)         : ${TASK_ROLE}"
  fi

  echo ""
}

# ---------------------------------------------------------------------------
# Validate required config
# ---------------------------------------------------------------------------

# Full validation — required for `spawn` only (network/role config must be present).
validate_spawn_config() {
  local missing=()

  [[ -z "${CLUSTER}" ]]          && missing+=("--cluster / ECS_DIAG_CLUSTER")
  [[ -z "${SUBNETS}" ]]          && missing+=("--subnets / ECS_DIAG_SUBNETS")
  [[ -z "${SECURITY_GROUPS}" ]]  && missing+=("--security-groups / ECS_DIAG_SECURITY_GROUPS")
  [[ -z "${EXECUTION_ROLE}" ]]   && missing+=("--execution-role / ECS_DIAG_EXECUTION_ROLE")
  [[ -z "${TASK_ROLE}" ]]        && missing+=("--task-role / ECS_DIAG_TASK_ROLE")

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required configuration:" >&2
    for m in "${missing[@]}"; do
      echo "  - ${m}" >&2
    done
    echo "" >&2
    echo "Tip: use --from-service <name> with --cluster to auto-discover these." >&2
    exit 1
  fi
  return 0
}

# Minimal validation — required for session/status/teardown (state-file subcommands).
# These only need --cluster to locate the state file; network/role config is not used.
validate_cluster_config() {
  if [[ -z "${CLUSTER}" ]]; then
    die "Missing required: --cluster / ECS_DIAG_CLUSTER"
  fi
}

# ---------------------------------------------------------------------------
# spawn
# ---------------------------------------------------------------------------
cmd_spawn() {
  echo "==> Registering task definition (family: ${TASK_FAMILY}) ..."

  local env_json
  env_json="$(build_env_json)"

  local container_def
  container_def=$(cat <<JSON
[
  {
    "name": "diag",
    "image": "${IMAGE}",
    "command": ["sleep", "infinity"],
    "cpu": 0,
    "essential": true,
    "linuxParameters": {
      "initProcessEnabled": true
    },
    "environment": ${env_json},
    "logConfiguration": {
      "logDriver": "awslogs",
      "options": {
        "awslogs-group": "/ecs/${TASK_FAMILY}",
        "awslogs-region": "${REGION}",
        "awslogs-stream-prefix": "ecs",
        "awslogs-create-group": "true"
      }
    }
  }
]
JSON
)

  local taskdef_arn
  taskdef_arn=$(aws_cmd ecs register-task-definition \
    --family "${TASK_FAMILY}" \
    --network-mode "awsvpc" \
    --requires-compatibilities "FARGATE" \
    --cpu "${CPU}" \
    --memory "${MEM}" \
    --execution-role-arn "${EXECUTION_ROLE}" \
    --task-role-arn "${TASK_ROLE}" \
    --container-definitions "${container_def}" \
    --query "taskDefinition.taskDefinitionArn" \
    --output text)

  echo "    Task def: ${taskdef_arn}"

  # Build network config
  local subnet_list sg_list
  subnet_list="$(csv_to_json_array "${SUBNETS}")"
  sg_list="$(csv_to_json_array "${SECURITY_GROUPS}")"

  local network_config
  network_config=$(cat <<JSON
{
  "awsvpcConfiguration": {
    "subnets": [${subnet_list}],
    "securityGroups": [${sg_list}],
    "assignPublicIp": "${ASSIGN_PUBLIC_IP}"
  }
}
JSON
)

  echo "==> Running task on cluster '${CLUSTER}' ..."

  local task_arn
  task_arn=$(aws_cmd ecs run-task \
    --cluster "${CLUSTER}" \
    --task-definition "${taskdef_arn}" \
    --launch-type "FARGATE" \
    --platform-version "LATEST" \
    --network-configuration "${network_config}" \
    --enable-execute-command \
    --query "tasks[0].taskArn" \
    --output text)

  [[ -z "${task_arn}" || "${task_arn}" == "None" ]] && \
    die "run-task returned no task ARN — check AWS output above"

  echo "    Task ARN: ${task_arn}"
  echo "${task_arn}" > "$(state_file)"

  # ---- Poll until RUNNING + ECS Exec agent RUNNING -------------------------
  echo "==> Polling for task RUNNING + ExecuteCommandAgent RUNNING ..."
  local attempts=0
  local max_attempts=60   # 60 × 5s = 5 min ceiling
  local last_status=""
  local exec_agent_status=""

  while [[ ${attempts} -lt ${max_attempts} ]]; do
    local task_json
    task_json=$(aws_cmd ecs describe-tasks \
      --cluster "${CLUSTER}" \
      --tasks "${task_arn}" \
      --query "tasks[0]" \
      --output json)

    last_status=$(echo "${task_json}" | python3 -c \
      "import sys,json; print(json.load(sys.stdin).get('lastStatus',''))")

    exec_agent_status=$(echo "${task_json}" | python3 -c "
import sys, json
t = json.load(sys.stdin)
for ma in t.get('containers',[{}])[0].get('managedAgents',[]):
    if ma.get('name') == 'ExecuteCommandAgent':
        print(ma.get('lastStatus',''))
        sys.exit(0)
print('PENDING')
")

    printf "    lastStatus=%-12s  ExecuteCommandAgent=%-10s\n" \
      "${last_status}" "${exec_agent_status}"

    if [[ "${last_status}" == "STOPPED" ]]; then
      local stop_reason
      stop_reason=$(echo "${task_json}" | python3 -c \
        "import sys,json; print(json.load(sys.stdin).get('stoppedReason','unknown'))")
      die "Task stopped unexpectedly: ${stop_reason}"
    fi

    if [[ "${last_status}" == "RUNNING" && "${exec_agent_status}" == "RUNNING" ]]; then
      break
    fi

    attempts=$(( attempts + 1 ))
    sleep 5
  done

  if [[ "${last_status}" != "RUNNING" || "${exec_agent_status}" != "RUNNING" ]]; then
    die "Timed out waiting for task to become ready (lastStatus=${last_status}, agent=${exec_agent_status})"
  fi

  echo ""
  echo "================================================================"
  echo "  Diagnostic container is READY"
  echo "  Task ARN : ${task_arn}"
  echo "  Cluster  : ${CLUSTER}"
  echo "================================================================"
  echo ""
  echo "To open a shell:"
  echo "  $(basename "$0") --cluster ${CLUSTER} ${FROM_SERVICE:+--from-service ${FROM_SERVICE} }session"
  echo ""
  echo "NOTE: If using a custom --task-role, verify it has the required"
  echo "  ssmmessages:CreateControlChannel, CreateDataChannel,"
  echo "  OpenControlChannel, OpenDataChannel permissions"
  echo "  or \`session\` will fail."
}

# ---------------------------------------------------------------------------
# session
# ---------------------------------------------------------------------------
cmd_session() {
  local sf
  sf="$(state_file)"
  [[ -f "${sf}" ]] || die "No diagnostic task found for cluster '${CLUSTER}' (family: ${TASK_FAMILY}); run 'spawn' first."

  local task_arn
  task_arn=$(cat "${sf}")
  [[ -z "${task_arn}" ]] && die "No diagnostic task found for cluster '${CLUSTER}' (family: ${TASK_FAMILY}); run 'spawn' first."

  # Verify task is still running
  local last_status
  last_status=$(aws_cmd ecs describe-tasks \
    --cluster "${CLUSTER}" \
    --tasks "${task_arn}" \
    --query "tasks[0].lastStatus" \
    --output text 2>/dev/null || echo "UNKNOWN")

  [[ "${last_status}" == "RUNNING" ]] || \
    die "Task is not RUNNING (lastStatus=${last_status}). Run 'spawn' to create a new one."

  # Determine command to exec.
  #
  # ECS Exec joins --command into a single string that the agent re-parses with
  # a shell, so any quoting/metacharacters in a multi-word command are lost
  # (pipes, parens, '<', quotes break — e.g. passwords with special chars).
  # To make one-off commands robust, base64-encode the payload locally and
  # decode it container-side as a single shell-safe token. Pass your whole
  # command as ONE quoted arg after --, e.g.:
  #   ecs-diag.sh session --cluster c -- 'PGPASSWORD=$P psql -c "select 1"'
  local exec_cmd="/bin/sh"
  if [[ ${#SESSION_ARGS[@]} -gt 0 ]]; then
    local payload b64
    payload="${SESSION_ARGS[*]}"
    b64="$(printf '%s' "${payload}" | base64 | tr -d '\n')"
    exec_cmd="/bin/sh -c \"echo ${b64} | base64 -d | /bin/sh\""
  fi

  echo "==> Opening ECS Exec session (command: ${exec_cmd}) ..."
  echo "    Task: ${task_arn}"
  echo ""

  aws_cmd ecs execute-command \
    --cluster "${CLUSTER}" \
    --task "${task_arn}" \
    --container "diag" \
    --interactive \
    --command "${exec_cmd}"
}

# ---------------------------------------------------------------------------
# teardown
# ---------------------------------------------------------------------------
cmd_teardown() {
  local sf
  sf="$(state_file)"

  if [[ ! -f "${sf}" ]]; then
    echo "No state file at ${sf} — nothing to do."
    return 0
  fi

  local task_arn
  task_arn=$(cat "${sf}")

  if [[ -z "${task_arn}" ]]; then
    echo "State file empty — removing it."
    rm -f "${sf}"
    return 0
  fi

  echo "==> Stopping task ${task_arn} ..."

  # Idempotent: ignore error if already stopped
  aws_cmd ecs stop-task \
    --cluster "${CLUSTER}" \
    --task "${task_arn}" \
    --reason "ecs-diag teardown" \
    --output text > /dev/null 2>&1 || true

  echo "    Task stop request sent."

  if [[ "${DEREGISTER_TASKDEF}" == "true" ]]; then
    echo "==> Deregistering task definition revision ..."
    local taskdef_arn
    taskdef_arn=$(aws_cmd ecs describe-tasks \
      --cluster "${CLUSTER}" \
      --tasks "${task_arn}" \
      --query "tasks[0].taskDefinitionArn" \
      --output text 2>/dev/null || echo "")

    if [[ -n "${taskdef_arn}" && "${taskdef_arn}" != "None" ]]; then
      aws_cmd ecs deregister-task-definition \
        --task-definition "${taskdef_arn}" \
        --output text > /dev/null
      echo "    Deregistered: ${taskdef_arn}"
    else
      echo "    Could not retrieve task-def ARN — skipping deregister."
    fi
  fi

  rm -f "${sf}"
  echo "==> State file removed.  Teardown complete."
}

# ---------------------------------------------------------------------------
# status
# ---------------------------------------------------------------------------
cmd_status() {
  local sf
  sf="$(state_file)"

  if [[ ! -f "${sf}" ]]; then
    echo "No state file at ${sf} — no active diagnostic task recorded."
    return 0
  fi

  local task_arn
  task_arn=$(cat "${sf}")
  [[ -z "${task_arn}" ]] && echo "State file empty." && return 0

  echo "Stored task ARN: ${task_arn}"
  echo ""

  local task_json
  task_json=$(aws_cmd ecs describe-tasks \
    --cluster "${CLUSTER}" \
    --tasks "${task_arn}" \
    --query "tasks[0]" \
    --output json 2>/dev/null || echo "{}")

  local last_status
  last_status=$(echo "${task_json}" | python3 -c \
    "import sys,json; d=json.load(sys.stdin); print(d.get('lastStatus','NOT_FOUND'))")

  local exec_agent_status
  exec_agent_status=$(echo "${task_json}" | python3 -c "
import sys, json
t = json.load(sys.stdin)
for ma in t.get('containers',[{}])[0].get('managedAgents',[]):
    if ma.get('name') == 'ExecuteCommandAgent':
        print(ma.get('lastStatus',''))
        sys.exit(0)
print('NOT_FOUND')
")

  echo "  lastStatus          : ${last_status}"
  echo "  ExecuteCommandAgent : ${exec_agent_status}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
parse_args "$@"

if [[ -z "${SUBCOMMAND}" ]]; then
  usage
  exit 1
fi

case "${SUBCOMMAND}" in
  spawn)
    # Discovery runs before validation so discovered values can satisfy requirements.
    resolve_from_service
    validate_spawn_config
    cmd_spawn
    ;;
  session)
    # Only --cluster needed to locate the state file; no network/role config required.
    validate_cluster_config
    cmd_session
    ;;
  teardown)
    validate_cluster_config
    cmd_teardown
    ;;
  status)
    validate_cluster_config
    cmd_status
    ;;
  *)
    die "Unknown subcommand: ${SUBCOMMAND}"
    ;;
esac
