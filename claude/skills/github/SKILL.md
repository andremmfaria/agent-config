---
name: github
description: GitHub gh CLI patterns for issues, PRs, checks, releases, and GraphQL API. Use when working with GitHub repositories, pull requests, or issues. Always prefer gh CLI over MCP.
---

## GitHub → `gh` CLI

> Run `check.sh` first to verify gh is installed and authenticated.

```bash
# Source credentials from keyring before running gh
export GITHUB_TOKEN=$(secret-tool lookup service github key GITHUB_TOKEN)
```

```bash
gh issue list --repo waratek/REPO
gh pr list/view/create --repo waratek/REPO
gh api /orgs/repos/waratek/REPO/pulls
gh api graphql -f query='{ viewer { login } }'
```

### Issues

```bash
gh issue list --repo waratek/REPO --state open --label bug
gh issue view ISSUE_NUMBER --repo waratek/REPO
gh issue create --repo waratek/REPO --title "Title" --body "Body" --label bug
gh issue close ISSUE_NUMBER --repo waratek/REPO
```

### Pull Requests

```bash
gh pr list --repo waratek/REPO --state open
gh pr view PR_NUMBER --repo waratek/REPO
gh pr create --repo waratek/REPO --title "Title" --body "Body" --base main
gh pr merge PR_NUMBER --repo waratek/REPO --squash
gh pr checks PR_NUMBER --repo waratek/REPO
gh pr review PR_NUMBER --approve --repo waratek/REPO
gh pr review PR_NUMBER --request-changes --body "Needs work" --repo waratek/REPO
```

### Releases

```bash
gh release list --repo waratek/REPO
gh release view TAG --repo waratek/REPO
gh release create TAG --repo waratek/REPO --title "Title" --notes "Notes"
```

### GraphQL API

```bash
gh api graphql -f query='{ viewer { login } }'
gh api graphql -f query='
  query($owner: String!, $repo: String!) {
    repository(owner: $owner, name: $repo) {
      pullRequests(last: 5, states: OPEN) {
        nodes { title number url }
      }
    }
  }
' -f owner=waratek -f repo=REPO
```

### REST API

```bash
gh api /repos/waratek/REPO/pulls
gh api /repos/waratek/REPO/issues?state=open
gh api /repos/waratek/REPO/actions/runs --jq '.workflow_runs[:5] | .[] | {id, name, status}'
```
