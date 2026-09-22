#!/usr/bin/env bash
set -euo pipefail

echo "==> Checking curl..."
if ! command -v curl &>/dev/null; then
  echo "❌ curl not found. Install via your package manager."
  exit 1
fi
echo "✅ curl $(curl --version | head -1)"

echo ""
echo "==> Checking env vars..."
if [[ -z "${SLACK_USER_TOKEN:-}" ]]; then
  echo "❌ Missing SLACK_USER_TOKEN"
  echo '   export SLACK_USER_TOKEN=$(secret-tool lookup service slack key SLACK_USER_TOKEN)'
  exit 1
fi
case "$SLACK_USER_TOKEN" in
  xoxp-*) echo "✅ SLACK_USER_TOKEN set (xoxp user token)" ;;
  xoxb-*) echo "⚠️  Token is xoxb (bot) — skill is designed for xoxp (user). Posts will appear as a bot and channels need invites." ;;
  *)      echo "⚠️  Token doesn't look like a Slack token (expected xoxp-…)" ;;
esac

echo ""
echo "==> Validating token (auth.test)..."
resp=$(curl -s -H "Authorization: Bearer $SLACK_USER_TOKEN" "https://slack.com/api/auth.test")
if [[ "$(echo "$resp" | jq -r .ok)" == "true" ]]; then
  echo "✅ Authed as $(echo "$resp" | jq -r .user) in workspace $(echo "$resp" | jq -r .team) ($(echo "$resp" | jq -r .url))"
else
  echo "❌ auth.test failed: $(echo "$resp" | jq -r .error)"
  exit 1
fi

echo ""
echo "==> Checking scopes..."
scopes=$(curl -s -i -H "Authorization: Bearer $SLACK_USER_TOKEN" \
  "https://slack.com/api/auth.test" | grep -i '^x-oauth-scopes:' | cut -d' ' -f2- | tr -d '\r')
echo "   Granted: ${scopes:-<none reported>}"
for s in chat:write channels:read channels:history channels:write groups:read groups:history \
         im:read im:write im:history mpim:read mpim:write mpim:history \
         users:read search:read reactions:read reactions:write files:write; do
  if [[ ",${scopes// /}," != *",$s,"* ]]; then
    echo "⚠️  Missing scope: $s"
  fi
done
echo "Done."
