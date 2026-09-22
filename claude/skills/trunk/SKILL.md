---
name: trunk
description: Use when querying Trunk.io flaky-tests data - quarantined tests, flaky/broken test status, failing tests in a time range, test case details - or checking PAT deploy-gate quarantine state. Auth via keyring token (service=trunk, key=TRUNK_API_TOKEN).
---

# Trunk.io → curl (REST API only)

## Overview

Trunk.io has NO query CLI. `trunk flakytests` and `trunk-analytics-cli` are write-path only (validate/upload/test). All reads go through the REST API: `https://api.trunk.io/v1`, header `x-api-token`, org-level token.

Quarantine toggle is UI/admin-only — no API endpoint exists. Rate limits undocumented — use paginated list calls, never per-test loops.

```bash
export TRUNK_API_TOKEN=$(secret-tool lookup service trunk key TRUNK_API_TOKEN)
# Waratek defaults
ORG=waratek
REPO_JSON='{"host":"github.com","owner":"waratek","name":"portal-automated-tests"}'
```

## Quick reference

| Task | Endpoint (all POST unless noted) |
|---|---|
| List quarantined tests | `/flaky-tests/list-quarantined-tests` |
| List flaky or broken tests | `/flaky-tests/list-unhealthy-tests` (`status`: `FLAKY` or `BROKEN`, required) |
| Distinct failing tests in time range | `/flaky-tests/list-failing-tests` (`start_time`/`end_time` required) |
| One test's details | `/flaky-tests/get-test-details` (`test_id` uuid required — from list responses) |
| Link Jira ticket to test case | `/flaky-tests/link-ticket-to-test-case` |
| Service health | GET `/status` (preflight check) |

All list endpoints: cursor pagination via `page_query{page_size (max 100), page_token}`; loop until `next_page_token` empty. Response `page.total_rows` gives full count on first call.

## List quarantined tests (paginated, complete)

```bash
page_token=""
: > /tmp/quarantined.jsonl
while : ; do
  resp=$(curl -sS -X POST "https://api.trunk.io/v1/flaky-tests/list-quarantined-tests" \
    -H "x-api-token: $TRUNK_API_TOKEN" -H "Content-Type: application/json" \
    -d "{\"repo\":$REPO_JSON,\"org_url_slug\":\"$ORG\",\"page_query\":{\"page_size\":100,\"page_token\":\"$page_token\"}}")
  echo "$resp" | jq -c '.quarantined_tests[]' >> /tmp/quarantined.jsonl
  page_token=$(echo "$resp" | jq -r '.page.next_page_token // empty')
  [ -z "$page_token" ] && break
done
wc -l /tmp/quarantined.jsonl
```

Each entry: `name`, `classname`, `parent` (= JUnit `<testsuite name>`), `file`, `variant`, `status` (HEALTHY|FLAKY|BROKEN), `quarantine_setting` (ALWAYS_QUARANTINE|AUTO_QUARANTINE), `quarantined_at`, `test_case_id` (uuid), `codeowners`.

Match a JUnit failure against this list on the `classname` + `name` tuple (tiebreak with `parent`/`file`).

## List flaky tests

```bash
curl -sS -X POST "https://api.trunk.io/v1/flaky-tests/list-unhealthy-tests" \
  -H "x-api-token: $TRUNK_API_TOKEN" -H "Content-Type: application/json" \
  -d "{\"repo\":$REPO_JSON,\"org_url_slug\":\"$ORG\",\"status\":\"FLAKY\",\"page_query\":{\"page_size\":100,\"page_token\":\"\"}}" \
  | jq -r '.tests[] | [.classname, .name, .status.value, (.quarantined|tostring), (.pull_requests_impacted_last_7d|tostring)] | @tsv'
```

Entries include `quarantined` (bool), `html_url` (Trunk UI link), `pull_requests_impacted_last_7d`, `id` (for get-test-details). Use `status: "BROKEN"` for always-failing tests. This endpoint answers "is X quarantined?" for status queries without cross-referencing the quarantine list.

Response `status.value` comes back lowercase (`"flaky"`/`"broken"`) even though the request `status` field is uppercase — don't hardcode uppercase matches. This endpoint paginates like the others: reuse the while-loop from the quarantine example when `total_rows` > page_size.

## Failing tests in a time range

```bash
curl -sS -X POST "https://api.trunk.io/v1/flaky-tests/list-failing-tests" \
  -H "x-api-token: $TRUNK_API_TOKEN" -H "Content-Type: application/json" \
  -d "{\"repo\":$REPO_JSON,\"org_url_slug\":\"$ORG\",\"start_time\":\"2026-07-20T00:00:00Z\",\"end_time\":\"2026-07-27T00:00:00Z\",\"page_query\":{\"page_size\":100,\"page_token\":\"\"}}" \
  | jq -r '.tests[] | [.classname, .name, .status.value] | @tsv'
```

## Per-test stats (get-test-details)

Failure rates and common-failure summaries exist ONLY here, not in the list endpoints. Needs the test `id` (uuid) from a list response.

```bash
curl -sS -X POST "https://api.trunk.io/v1/flaky-tests/get-test-details" \
  -H "x-api-token: $TRUNK_API_TOKEN" -H "Content-Type: application/json" \
  -d "{\"repo\":$REPO_JSON,\"org_url_slug\":\"$ORG\",\"test_id\":\"<uuid>\"}" \
  | jq '{name: .test.name, status: .test.status.value, rate_7d: .test.failure_rate_last_7d, rate_24h: .test.failure_rate_last_24h, prs_7d: .test.pull_requests_impacted_last_7d}'
```

`most_common_failures` in the response is feature-flagged (request access from Trunk). One call per test: only fetch details for a small set (e.g. the failures in one run), never sweep all tests.

## Gotchas

- **Quarantine changes are UI-only** (right-click row, admin required). No API. Webhook event `test_case.quarantining_setting_changed` exists (Svix, UI-configured) if automation is ever needed.
- **Uploader controls exit codes by default**: `trunk-analytics-cli upload` (and the `trunk-io/analytics-uploader` GH action) reds the step on unquarantined failures unless env `TRUNK_DISABLE_QUARANTINING=true` is set (no action input exists for it, env var only). Relevant to the PAT deploy gate (PAT-750).
- **404/HTML response**: check the path — API is `POST` with JSON body even for list operations; a GET to a list endpoint returns an error page.
- Repos other than portal-automated-tests: swap `name` in `REPO_JSON`; token is org-wide.
- **No skipped-tests API**: per-test statuses are only healthy/flaky/broken + quarantine state. Skipped counts come from your JUnit XML, not Trunk (verified against the full OpenAPI spec).
