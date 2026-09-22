---
name: oci
description: Oracle Cloud Infrastructure (OCI) CLI patterns for querying and modifying resources (Compute, Object Storage, Networking/VCN, Block/Boot Volumes, IAM, Database, Load Balancer, Vault/Secrets, Logging). Use when working with any OCI service. Always prefer oci CLI over MCP.
---

## OCI CLI

> Run `check.sh` first to verify the oci CLI is installed and auth is configured.

CLI lives in a dedicated venv (`~/.local/lib/oracle-cli`) symlinked to `~/.local/bin/oci`.

```bash
oci <service> <resource> <action> --compartment-id <ocid> [--region <region>]
```

### Auth

Two models. Pick per tenancy setup:

```bash
# 1. API-key (config file ~/.oci/config, key ~/.oci/oci_api_key.pem)
oci setup config          # interactive: writes config + generates keypair
# then upload ~/.oci/oci_api_key_public.pem in Console -> User -> API Keys

# 2. SSO / IAM identity-domain session token (no static key)
oci session authenticate  # browser login -> token profile
oci <cmd> --auth security_token --profile <token-profile>
export OCI_CLI_AUTH=security_token   # make it the default for the shell
```

Profiles select credentials: `--profile NAME` (sections in `~/.oci/config`). Set a default region per profile or pass `--region`.

> **This host:** `[DEFAULT]` profile is incomplete (no user/key/fingerprint) — always pass `--profile API` (API-key auth). Never use session auth here.

Almost every read/list needs a `--compartment-id` (root compartment = tenancy OCID). Discover compartments first:

```bash
# Tenancy OCID lives in config
grep -E '^tenancy' ~/.oci/config

export C=$(grep -m1 '^tenancy' ~/.oci/config | cut -d= -f2)   # root compartment
oci iam compartment list --compartment-id "$C" --all \
  --query 'data[].{name:name,id:id,state:"lifecycle-state"}' --output table
```

### Query patterns

OCI uses `--query` (JMESPath, same engine as aws) and `--output table|json`. Note: data is under the `data` key, and field names are kebab-case (quote them in JMESPath, e.g. `"display-name"`).

```bash
# Regions / availability domains
oci iam region list --output table
oci iam availability-domain list --compartment-id "$C" --output table

# Compute instances
oci compute instance list --compartment-id "$C" --all \
  --query 'data[].{name:"display-name",state:"lifecycle-state",shape:shape,id:id}' \
  --output table
oci compute instance get --instance-id <ocid> \
  --query 'data.{name:"display-name",state:"lifecycle-state"}'
# Instance public/private IP (via VNIC attachments)
oci compute instance list-vnics --instance-id <ocid> \
  --query 'data[].{priv:"private-ip",pub:"public-ip"}' --output table

# Object Storage
oci os ns get                                              # tenancy namespace
oci os bucket list --compartment-id "$C" --output table
oci os object list --bucket-name BUCKET --output table
oci os object get --bucket-name BUCKET --name path/file.json --file /tmp/file.json
oci os object put --bucket-name BUCKET --name path/file.json --file ./file.json

# Networking (VCN)
oci network vcn list --compartment-id "$C" --output table
oci network subnet list --compartment-id "$C" --vcn-id <vcn-ocid> --output table
oci network security-list list --compartment-id "$C" --vcn-id <vcn-ocid> --output table

# Block / Boot volumes
oci bv volume list --compartment-id "$C" --output table
oci bv boot-volume list --compartment-id "$C" --availability-domain <AD> --output table

# Database
oci db system list --compartment-id "$C" --output table
oci db autonomous-database list --compartment-id "$C" --output table

# Load balancer
oci lb load-balancer list --compartment-id "$C" --output table

# Vault / Secrets
oci vault secret list --compartment-id "$C" --output table
oci secrets secret-bundle get --secret-id <ocid> \
  --query 'data."secret-bundle-content".content' --raw-output | base64 -d

# IAM
oci iam user list --compartment-id "$C" --output table
oci iam policy list --compartment-id "$C" --output table
```

### Modify patterns

```bash
# Compute lifecycle
oci compute instance action --instance-id <ocid> --action STOP    # START|STOP|RESET|SOFTRESET
oci compute instance terminate --instance-id <ocid> --preserve-boot-volume false

# Object Storage
oci os object bulk-upload --bucket-name BUCKET --src-dir ./dist --prefix prefix/
oci os object bulk-download --bucket-name BUCKET --download-dir ./out --prefix prefix/
oci os object delete --bucket-name BUCKET --name path/file.json

# Tags on any resource
oci compute instance update --instance-id <ocid> \
  --freeform-tags '{"env":"prod"}'
```

### Useful flags

```bash
--all                    # auto-paginate list calls (default returns one page)
--output json|table      # table needs a --query projecting to flat objects
--query 'JMESPath'       # data lives under `data`; kebab-case keys need quotes
--raw-output             # strip JSON quoting (for piping a single string value)
--profile NAME           # select credentials/region from ~/.oci/config
--region us-ashburn-1    # override profile region
--auth security_token    # SSO session-token auth instead of API key
--dry-run                # supported on some create/update ops
export OCI_CLI_PROFILE / OCI_CLI_REGION / OCI_CLI_AUTH   # shell-wide defaults
```

### Notes

- Compartments are hierarchical; `--all` + `--compartment-id-in-subtree true` (on supported list calls) recurses.
- Most resources are region-scoped except IAM (home-region). Object Storage namespace is tenancy-global.
- OCIDs are the canonical identifiers everywhere (`ocid1.<type>.oc1..<hash>`).
- `chmod 600 ~/.oci/config ~/.oci/oci_api_key.pem` — CLI warns on loose perms.
