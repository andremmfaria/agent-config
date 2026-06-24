#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Run GitHub Actions workflows locally with act.

Usage:
  ./scripts/run-gh-workflows-locally.sh [workflow ...]

Examples:
  ./scripts/run-gh-workflows-locally.sh
  ./scripts/run-gh-workflows-locally.sh pre-commit.yml
  ./scripts/run-gh-workflows-locally.sh validate-config.yml shellcheck.yml

Notes:
  - Requires: act, Docker
  - Uses workflow_dispatch for all runs
  - If .secrets.act exists at repo root, it is passed to act automatically
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v act >/dev/null 2>&1; then
  cat >&2 <<'INSTALL'
Error: act is not installed or not available in PATH.

Install act:
  macOS (Homebrew):  brew install act
  Linux (curl):      curl --proto '=https' --tlsv1.2 -sSf \
                       https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
  GitHub releases:   https://github.com/nektos/act/releases

Then re-run this script.
INSTALL
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: Docker is not installed or not available in PATH." >&2
  exit 1
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
cd "$REPO_ROOT"

WORKFLOWS=("$@")
if [[ ${#WORKFLOWS[@]} -eq 0 ]]; then
  WORKFLOWS=("pre-commit.yml" "validate-config.yml" "shellcheck.yml")
fi

EVENT_FILE=$(mktemp)
cleanup() {
  rm -f "$EVENT_FILE"
}
trap cleanup EXIT

cat > "$EVENT_FILE" <<'EOF'
{
  "ref": "refs/heads/main",
  "repository": {
    "full_name": "local/agent-config"
  }
}
EOF

COMMON_ARGS=(workflow_dispatch --container-architecture linux/amd64 --eventpath "$EVENT_FILE")

if [[ -f .secrets.act ]]; then
  COMMON_ARGS+=(--secret-file .secrets.act)
fi

for workflow in "${WORKFLOWS[@]}"; do
  workflow_path=".github/workflows/$workflow"
  if [[ ! -f "$workflow_path" ]]; then
    echo "Error: workflow not found: $workflow_path" >&2
    exit 1
  fi

  echo "Running $workflow_path"
  act "${COMMON_ARGS[@]}" -W "$workflow_path"
done
