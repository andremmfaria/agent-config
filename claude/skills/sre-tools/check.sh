#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# 1. aws CLI
# ---------------------------------------------------------------------------
echo "==> Checking aws CLI..."
if ! command -v aws &>/dev/null; then
  echo "❌ aws CLI not found."
  echo "   Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
  echo "   macOS:   brew install awscli"
  echo "   Linux:   curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o awscliv2.zip && unzip awscliv2.zip && sudo ./aws/install"
  exit 1
fi
echo "✅ $(aws --version)"

# ---------------------------------------------------------------------------
# 2. session-manager-plugin  — required for `session` (ECS Exec)
# ---------------------------------------------------------------------------
echo ""
echo "==> Checking session-manager-plugin..."
if ! command -v session-manager-plugin &>/dev/null; then
  echo "❌ session-manager-plugin not found."
  echo "   Required for the 'session' subcommand (ECS Exec / aws ecs execute-command)."
  echo "   Install: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html"
  echo "   macOS:   brew install --cask session-manager-plugin"
  exit 1
fi
echo "✅ session-manager-plugin found: $(command -v session-manager-plugin)"

# ---------------------------------------------------------------------------
# 3. python3  — used by ecs-diag.sh for JSON parsing during spawn/--from-service
# ---------------------------------------------------------------------------
echo ""
echo "==> Checking python3..."
if ! command -v python3 &>/dev/null; then
  echo "❌ python3 not found."
  echo "   ecs-diag.sh uses python3 to parse JSON (spawn polling, --from-service discovery)."
  echo "   Install: https://www.python.org/downloads/"
  echo "   macOS:   brew install python3"
  echo "   Linux:   sudo apt install python3  or  sudo yum install python3"
  exit 1
fi
echo "✅ $(python3 --version)"

# ---------------------------------------------------------------------------
# 4. ecs-diag.sh — exists, is executable, passes bash -n
# ---------------------------------------------------------------------------
echo ""
echo "==> Checking ecs-diag.sh..."
ECS_DIAG="${SKILL_DIR}/ecs-diag.sh"
if [[ ! -f "${ECS_DIAG}" ]]; then
  echo "❌ ecs-diag.sh not found at ${ECS_DIAG}"
  exit 1
fi
if [[ ! -x "${ECS_DIAG}" ]]; then
  echo "❌ ecs-diag.sh is not executable: ${ECS_DIAG}"
  echo "   Fix: chmod +x ${ECS_DIAG}"
  exit 1
fi
if ! bash -n "${ECS_DIAG}" 2>&1; then
  echo "❌ ecs-diag.sh failed bash syntax check."
  exit 1
fi
echo "✅ ecs-diag.sh found, executable, syntax OK: ${ECS_DIAG}"

# ---------------------------------------------------------------------------
# 5. AWS auth  — soft check (warn, do not fail)
# ---------------------------------------------------------------------------
echo ""
echo "==> Checking AWS auth..."
if aws sts get-caller-identity &>/dev/null 2>&1; then
  identity=$(aws sts get-caller-identity --output json 2>/dev/null)
  account=$(echo "$identity" | python3 -c "import json,sys; print(json.load(sys.stdin)['Account'])" 2>/dev/null || echo "unknown")
  arn=$(echo "$identity" | python3 -c "import json,sys; print(json.load(sys.stdin)['Arn'])" 2>/dev/null || echo "unknown")
  echo "✅ Authenticated"
  echo "   Account: ${account}"
  echo "   ARN:     ${arn}"
else
  echo "⚠️  No default credentials resolved."
  echo "   spawn/session require an authenticated profile. Pass --profile on each call, e.g.:"
  echo "     ecs-diag.sh spawn --profile AdminPortalProd --cluster portal-prod ..."
  echo "   Or export AWS_PROFILE before running."
fi

# ---------------------------------------------------------------------------
# 6. TTY note  — operational reminder, not a failure
# ---------------------------------------------------------------------------
echo ""
echo "==> NOTE: interactive 'session' requires a real TTY."
echo "   'aws ecs execute-command --interactive' exits on EOF without a controlling terminal."
echo "   When scripting non-interactively, wrap it in a PTY, e.g.:"
echo "     python3 -c \"import pty, sys; pty.spawn(sys.argv[1:])\" \\"
echo "       ecs-diag.sh session --cluster <CLUSTER>"

echo ""
echo "==> All checks passed. Ready to use ecs-diag.sh."
