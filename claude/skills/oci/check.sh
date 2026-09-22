#!/usr/bin/env bash
set -euo pipefail

echo "==> Checking oci CLI..."
if ! command -v oci &>/dev/null; then
  echo "❌ oci CLI not found."
  echo "   Installed here in a dedicated venv symlinked to ~/.local/bin/oci:"
  echo "     python3 -m venv ~/.local/lib/oracle-cli"
  echo "     ~/.local/lib/oracle-cli/bin/pip install oci-cli"
  echo "     ln -sf ~/.local/lib/oracle-cli/bin/oci ~/.local/bin/oci"
  echo "   Docs: https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm"
  exit 1
fi
echo "✅ oci $(oci --version)"

echo ""
echo "==> Checking config..."
if [[ ! -f ~/.oci/config ]]; then
  echo "⚠️  No ~/.oci/config found."
  echo "   API key:  oci setup config      (then upload public key in Console -> User -> API Keys)"
  echo "   SSO:      oci session authenticate  (then use --auth security_token)"
  exit 0
fi
echo "✅ ~/.oci/config present"
profiles=$(grep -oE '^\[[^]]+\]' ~/.oci/config | tr -d '[]' | paste -sd, -)
echo "   Profiles: ${profiles:-none}"

echo ""
echo "==> Checking auth (oci iam region list, per profile)..."
authflag=""
okprofile=""
for p in $(grep -oE '^\[[^]]+\]' ~/.oci/config | tr -d '[]'); do
  if oci iam region list --profile "$p" &>/dev/null 2>&1; then
    okprofile="$p"
    break
  fi
done
if [[ -z "$okprofile" ]] && oci iam region list --auth security_token &>/dev/null 2>&1; then
  okprofile="DEFAULT"
  authflag=" (SSO session token)"
  echo "   note: authenticated via session token — export OCI_CLI_AUTH=security_token"
fi
if [[ -n "$okprofile" ]]; then
  echo "✅ Authenticated${authflag} — working profile: $okprofile"
  [[ "$okprofile" != "DEFAULT" ]] && echo "   note: pass --profile $okprofile (or export OCI_CLI_PROFILE=$okprofile)"
  tenancy=$(grep -m1 '^tenancy' ~/.oci/config 2>/dev/null | cut -d= -f2 || echo unknown)
  echo "   Tenancy (root compartment): $tenancy"
  if [[ -n "$authflag" ]]; then
    oci session validate --auth security_token 2>/dev/null | head -1 | sed 's/^/   /' || true
  fi
else
  echo "⚠️  Auth call failed. Try:"
  echo "   - SSO:      oci session authenticate ; export OCI_CLI_AUTH=security_token"
  echo "   - SSO:      oci session refresh   (if token expired)"
  echo "   - API key:  verify fingerprint/key_file in ~/.oci/config match Console API key"
  echo "   - chmod 600 ~/.oci/config ~/.oci/oci_api_key.pem"
fi

echo ""
echo "==> Done."
