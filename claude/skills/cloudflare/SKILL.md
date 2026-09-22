---
name: cloudflare
description: Cloudflare CLI patterns via flarectl (DNS, zones) and curl (Workers, zone create). Single token $CLOUDFLARE_INVESTIGATION_TOKEN for read and write. Use when working with Cloudflare DNS, Workers, or zones.
---

## Cloudflare → `flarectl` (DNS/Zones) + `curl` (Workers)

> Run `check.sh` first to verify flarectl is installed and env vars are set.

```bash
# Source credentials from keyring before running flarectl/curl
export CLOUDFLARE_ACCOUNT=$(secret-tool lookup service cloudflare key CLOUDFLARE_ACCOUNT)
export CLOUDFLARE_BASE=$(secret-tool lookup service cloudflare key CLOUDFLARE_BASE)
export CLOUDFLARE_INVESTIGATION_TOKEN=$(secret-tool lookup service cloudflare key CLOUDFLARE_INVESTIGATION_TOKEN)

# Single token for both read and write. Despite the name, this token carries
# account-level zone.create, DNS edit and Rulesets edit. It is account-owned,
# so /user/tokens/verify returns success:false — that says nothing about scope.
# flarectl uses CF_API_TOKEN — set it inline:
#   CF_API_TOKEN=$CLOUDFLARE_INVESTIGATION_TOKEN flarectl ...
```

### Zones

```bash
# List all zones
CF_API_TOKEN=$CLOUDFLARE_INVESTIGATION_TOKEN flarectl zone list

# Zone info
CF_API_TOKEN=$CLOUDFLARE_INVESTIGATION_TOKEN flarectl zone info --zone example.com

# Create a zone (flarectl cannot do this — use the API)
curl -s -X POST -H "Authorization: Bearer $CLOUDFLARE_INVESTIGATION_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"example.com\",\"account\":{\"id\":\"$CLOUDFLARE_ACCOUNT\"},\"type\":\"full\"}" \
  "https://api.cloudflare.com/client/v4/zones" \
  | jq -c '{success, id:.result.id, status:.result.status, ns:.result.name_servers}'
# Zone stays "pending" until the registrar's nameservers point at the returned pair.

# Purge cache
CF_API_TOKEN=$CLOUDFLARE_INVESTIGATION_TOKEN flarectl zone purge --zone example.com --everything
```

### DNS records

```bash
# List DNS records
CF_API_TOKEN=$CLOUDFLARE_INVESTIGATION_TOKEN flarectl dns list --zone example.com

# Create DNS record
CF_API_TOKEN=$CLOUDFLARE_INVESTIGATION_TOKEN flarectl dns create \
  --zone example.com --name www --type A --content 1.2.3.4

CF_API_TOKEN=$CLOUDFLARE_INVESTIGATION_TOKEN flarectl dns create \
  --zone example.com --name sub --type CNAME --content target.example.com --proxy

# Delete DNS record
CF_API_TOKEN=$CLOUDFLARE_INVESTIGATION_TOKEN flarectl dns delete \
  --zone example.com --id RECORD_ID
```

### Firewall rules

```bash
CF_API_TOKEN=$CLOUDFLARE_INVESTIGATION_TOKEN flarectl firewall rules list --zone example.com
```

---

## Workers → `curl` (flarectl does not cover Workers)

```bash
# List Workers scripts
curl -s -H "Authorization: Bearer $CLOUDFLARE_INVESTIGATION_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT/workers/scripts"

# Get Worker script content
curl -s -H "Authorization: Bearer $CLOUDFLARE_INVESTIGATION_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/$CLOUDFLARE_ACCOUNT/workers/scripts/SCRIPT_NAME"
```
