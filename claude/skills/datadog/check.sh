#!/usr/bin/env bash
set -euo pipefail

echo "==> Checking ddogctl..."
if ! command -v ddogctl &>/dev/null; then
  echo "❌ ddogctl not found."
  echo "   Install: pip install ddogctl"
  echo "        or: pipx install ddogctl"
  echo "        or: uv pip install ddogctl"
  echo "   Docs: https://github.com/srgfrancisco/ddogctl"
  exit 1
fi
echo "✅ ddogctl $(ddogctl --version 2>/dev/null | head -1 || echo 'installed')"

echo ""
echo "==> Checking env vars..."
missing=()
# Support both naming conventions (DD_* preferred by ddogctl, DATADOG_* legacy)
if [[ -z "${DD_API_KEY:-}" && -z "${DATADOG_API_KEY:-}" ]]; then
  missing+=("DD_API_KEY (or DATADOG_API_KEY)")
fi
if [[ -z "${DD_APP_KEY:-}" && -z "${DATADOG_APP_KEY:-}" ]]; then
  missing+=("DD_APP_KEY (or DATADOG_APP_KEY)")
fi

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "❌ Missing env vars: ${missing[*]}"
  echo "   ddogctl uses DD_API_KEY and DD_APP_KEY"
  echo "   DD_SITE is optional (default: datadoghq.com). Shortcuts: us, eu, us3, us5, ap1, gov"
  exit 1
fi

# Normalise to ddogctl expected names if using legacy names
export DD_API_KEY="${DD_API_KEY:-$DATADOG_API_KEY}"
export DD_APP_KEY="${DD_APP_KEY:-$DATADOG_APP_KEY}"
export DD_SITE="${DD_SITE:-${DATADOG_SITE:-}}"

echo "✅ DD_API_KEY set"
echo "✅ DD_APP_KEY set"
[[ -n "${DD_SITE:-}" ]] && echo "✅ DD_SITE=${DD_SITE}" || echo "ℹ️  DD_SITE not set (defaulting to datadoghq.com)"

echo ""
echo "==> All checks passed. Ready to use ddogctl."
