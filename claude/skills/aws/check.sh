#!/usr/bin/env bash
set -euo pipefail

echo "==> Checking aws CLI..."
if ! command -v aws &>/dev/null; then
  echo "❌ aws CLI not found."
  echo "   Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
  echo "   macOS:   brew install awscli"
  echo "   Linux:   curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o awscliv2.zip && unzip awscliv2.zip && sudo ./aws/install"
  exit 1
fi
echo "✅ $(aws --version)"

echo ""
echo "==> Checking auth configuration..."
if aws sts get-caller-identity &>/dev/null 2>&1; then
  identity=$(aws sts get-caller-identity --output json 2>/dev/null)
  account=$(echo "$identity" | python3 -c "import json,sys; print(json.load(sys.stdin)['Account'])" 2>/dev/null || echo "unknown")
  arn=$(echo "$identity" | python3 -c "import json,sys; print(json.load(sys.stdin)['Arn'])" 2>/dev/null || echo "unknown")
  echo "✅ Authenticated"
  echo "   Account: $account"
  echo "   ARN:     $arn"
else
  echo "⚠️  No default credentials found."
  echo "   Options:"
  echo "   - Set AWS_PROFILE env var: export AWS_PROFILE=prod"
  echo "   - Set AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY"
  echo "   - Run: aws configure"
  echo "   Always pass --profile and --region explicitly in commands."
fi

echo ""
echo "==> All checks passed. Ready to use aws CLI."
