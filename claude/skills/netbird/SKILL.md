---
name: netbird
description: NetBird CLI and Management API patterns — peer connect/disconnect/status, groups, policies, nameserver groups, networks, setup keys. Use when working with NetBird overlay networking, enrolling peers, managing access policies, or configuring split-DNS.
---

## NetBird → `netbird` CLI (peer control) + `curl` (management API)

Auth for management API — source PAT from keyring before running:

```bash
export NETBIRD_PAT=$(secret-tool lookup service netbird key NETBIRD_PAT)

curl -s -H "Authorization: Token $NETBIRD_PAT" -H "Content-Type: application/json" \
  https://api.netbird.io/api/...
```

Self-hosted: replace `https://api.netbird.io` with your management URL.

---

## CLI — local peer control

```bash
# Connect / disconnect
netbird up                                    # connect using existing config
netbird up -k <setup-key>                     # enroll + connect with setup key
netbird up -k <setup-key> -n <hostname>       # custom hostname on enroll
netbird down                                  # disconnect

# Status
netbird status                                # summary
netbird status -d                             # detailed (peers, routes, DNS)
netbird status --json                         # machine-readable
netbird status --filter-by-status connected   # only connected peers
netbird status --ipv4                         # print this peer's overlay IP only

# Networks / routes
netbird networks list                         # list available networks
netbird networks select <network-id>          # opt in to a network
netbird networks deselect <network-id>        # opt out

# Debug
netbird debug bundle                          # create debug tarball
netbird debug log level debug                 # set log level
netbird debug trace <dst-ip>                  # trace packet through firewall

# Service (Linux)
netbird service install
netbird service start
netbird service stop
netbird service status
```

Env vars map flags: `NB_SETUP_KEY`, `NB_MANAGEMENT_URL`, `NB_HOSTNAME`.

---

## Management API — groups

```bash
# List groups
curl -s -H "Authorization: Token $NETBIRD_PAT" \
  https://api.netbird.io/api/groups | jq '.[].name'

# Create group
curl -s -X POST -H "Authorization: Token $NETBIRD_PAT" \
  -H "Content-Type: application/json" \
  https://api.netbird.io/api/groups \
  -d '{"name": "staging-access"}'

# Add peer to group  (PATCH replaces peers list — always include existing peers)
curl -s -X PUT -H "Authorization: Token $NETBIRD_PAT" \
  -H "Content-Type: application/json" \
  https://api.netbird.io/api/groups/<group-id> \
  -d '{"name": "staging-access", "peers": ["<peer-id-1>", "<peer-id-2>"]}'

# Delete group
curl -s -X DELETE -H "Authorization: Token $NETBIRD_PAT" \
  https://api.netbird.io/api/groups/<group-id>
```

---

## Management API — peers

```bash
# List peers
curl -s -H "Authorization: Token $NETBIRD_PAT" \
  https://api.netbird.io/api/peers | jq '.[] | {id, name, ip: .ip, connected}'

# Get peer by ID
curl -s -H "Authorization: Token $NETBIRD_PAT" \
  https://api.netbird.io/api/peers/<peer-id>

# Update peer (rename, set login expiry)
curl -s -X PUT -H "Authorization: Token $NETBIRD_PAT" \
  -H "Content-Type: application/json" \
  https://api.netbird.io/api/peers/<peer-id> \
  -d '{"name": "routing-staging", "login_expiration_enabled": false}'

# Delete peer (deregister)
curl -s -X DELETE -H "Authorization: Token $NETBIRD_PAT" \
  https://api.netbird.io/api/peers/<peer-id>
```

---

## Management API — setup keys

```bash
# List setup keys
curl -s -H "Authorization: Token $NETBIRD_PAT" \
  https://api.netbird.io/api/setup-keys | jq '.[] | {id, name, type, used_times, expires}'

# Create setup key (reusable, expires in 30 days, auto-joins groups)
curl -s -X POST -H "Authorization: Token $NETBIRD_PAT" \
  -H "Content-Type: application/json" \
  https://api.netbird.io/api/setup-keys \
  -d '{
    "name": "routing-staging",
    "type": "reusable",
    "expires_in": 2592000,
    "auto_groups": ["<group-id>"],
    "usage_limit": 1
  }'

# Revoke setup key
curl -s -X DELETE -H "Authorization: Token $NETBIRD_PAT" \
  https://api.netbird.io/api/setup-keys/<key-id>
```

---

## Management API — policies

```bash
# List policies
curl -s -H "Authorization: Token $NETBIRD_PAT" \
  https://api.netbird.io/api/policies | jq '.[] | {id, name, enabled}'

# Create policy (src group → dst group, TCP 443)
curl -s -X POST -H "Authorization: Token $NETBIRD_PAT" \
  -H "Content-Type: application/json" \
  https://api.netbird.io/api/policies \
  -d '{
    "name": "engineering-to-staging",
    "enabled": true,
    "rules": [{
      "name": "engineering-to-staging",
      "enabled": true,
      "action": "accept",
      "bidirectional": true,
      "protocol": "tcp",
      "ports": ["443", "8080"],
      "sources": [{"id": "<staging-access-group-id>"}],
      "destinations": [{"id": "<routing-staging-group-id>"}]
    }]
  }'

# Delete policy
curl -s -X DELETE -H "Authorization: Token $NETBIRD_PAT" \
  https://api.netbird.io/api/policies/<policy-id>
```

---

## Management API — DNS nameserver groups

```bash
# List nameserver groups
curl -s -H "Authorization: Token $NETBIRD_PAT" \
  https://api.netbird.io/api/dns/nameservers | jq '.[] | {id, name, domains, groups}'

# Create nameserver group (split-DNS for staging.waratek.com)
curl -s -X POST -H "Authorization: Token $NETBIRD_PAT" \
  -H "Content-Type: application/json" \
  https://api.netbird.io/api/dns/nameservers \
  -d '{
    "name": "staging-internal",
    "description": "Route staging.waratek.com to staging VPC DNS",
    "nameservers": [{"ip": "10.x.x.2", "ns_type": "udp", "port": 53}],
    "enabled": true,
    "groups": ["<staging-access-group-id>"],
    "primary": false,
    "domains": ["staging.waratek.com"],
    "search_domains_enabled": false
  }'

# Update nameserver group
curl -s -X PUT -H "Authorization: Token $NETBIRD_PAT" \
  -H "Content-Type: application/json" \
  https://api.netbird.io/api/dns/nameservers/<ns-group-id> \
  -d '{ ...same body with changes... }'

# Delete
curl -s -X DELETE -H "Authorization: Token $NETBIRD_PAT" \
  https://api.netbird.io/api/dns/nameservers/<ns-group-id>
```

---

## Management API — networks and resources

```bash
# List networks
curl -s -H "Authorization: Token $NETBIRD_PAT" \
  https://api.netbird.io/api/networks | jq '.[] | {id, name}'

# Create network
curl -s -X POST -H "Authorization: Token $NETBIRD_PAT" \
  -H "Content-Type: application/json" \
  https://api.netbird.io/api/networks \
  -d '{"name": "staging-vpc", "description": "Staging VPC resources"}'

# Add resource to network (domain wildcard)
curl -s -X POST -H "Authorization: Token $NETBIRD_PAT" \
  -H "Content-Type: application/json" \
  "https://api.netbird.io/api/networks/<network-id>/resources" \
  -d '{
    "name": "staging-services",
    "address": "staging.waratek.com",
    "enabled": true,
    "groups": ["<staging-access-group-id>"]
  }'

# List network routers (routing peers)
curl -s -H "Authorization: Token $NETBIRD_PAT" \
  "https://api.netbird.io/api/networks/<network-id>/routers" | jq '.[].peer_id'
```

---

## Management API — events (audit log)

```bash
# List recent events
curl -s -H "Authorization: Token $NETBIRD_PAT" \
  "https://api.netbird.io/api/events" | jq '.[] | {timestamp, activity, meta}'
```
