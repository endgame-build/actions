# CROSS_REPO_READ_TOKEN

## What it is

A fine-grained GitHub Personal Access Token with `contents:read` on specific repos. Lets the weekly digest workflow read `CHANGELOG.md` from multiple repositories.

## Why it's needed

The weekly digest runs as a scheduled workflow in `endgame-build/actions`. GitHub's `GITHUB_TOKEN` only has access to the repo it runs in. To read changelogs from atelier, jira-cli, toc-flow, and workitems-cli, the workflow needs a token with cross-repo read access.

Without this token, the weekly digest cannot run. Per-merge changelog PRs are not affected.

## Where to set it

| Scope | Repo |
|-------|------|
| **Repo secret** on `endgame-build/actions` | Only needed here — the digest workflow runs in this repo |

This token does NOT need to be org-level or set on spoke repos.

## How to create

### Step 1: Generate a fine-grained PAT

```bash
# Open the token creation page
open "https://github.com/settings/tokens?type=beta"
```

Or navigate: GitHub > Settings > Developer settings > Personal access tokens > Fine-grained tokens > Generate new token.

### Step 2: Configure the token

| Setting | Value |
|---------|-------|
| Token name | `changelog-digest-read` |
| Expiration | 1 year (max) |
| Resource owner | `endgame-build` |
| Repository access | **All repositories** |
| Permissions | **Contents: Read-only** (nothing else) |

Using **all repositories** avoids having to update the token every time a new repo adopts the changelog pipeline. The token is read-only — the blast radius is minimal.

### Step 3: Generate and copy

Click **Generate token**. Copy the value — it starts with `github_pat_`.

**Important:** Use a bot/service account, not a personal account. If the account owner leaves the org, the token is invalidated.

### Future: GitHub App

The long-term replacement is a GitHub App with `contents:read` installed org-wide. Benefits: auto-rotating tokens (1-hour lifetime), clean audit trail, no manual expiry management. Requires org admin to create. Tracked for later migration.

## How to set

```bash
# Paste the github_pat_ token when prompted
gh secret set CROSS_REPO_READ_TOKEN --repo endgame-build/actions
```

**Description for the GitHub settings page:**

> Fine-grained PAT (contents:read) for the weekly changelog digest. Reads CHANGELOG.md from atelier, jira-cli, toc-flow, workitems-cli. Bot/service account owned. Expires annually — rotate before expiry. See endgame-build/actions/docs/secrets/CROSS_REPO_READ_TOKEN.md.

**Request message for org admin:**

> The weekly changelog digest needs a `CROSS_REPO_READ_TOKEN` on `endgame-build/actions`. It's a fine-grained PAT with contents:read on atelier, jira-cli, toc-flow, and workitems-cli. Create at github.com/settings/tokens?type=beta under a bot account, then: `gh secret set CROSS_REPO_READ_TOKEN --repo endgame-build/actions`. Expires in 1 year — set a rotation reminder. Tracked in endgame-build/atelier#149.

## Security

- **Blast radius if leaked:** Read-only access to source code across the org. No write access, no admin.
- **Rotation:** Generate a new token, update the secret, revoke the old token. Annual rotation recommended.
- **Expiry:** Fine-grained PATs have a maximum lifetime of 1 year. The weekly digest will silently skip repos it can't access (with a warning in the Slack message) when the token expires.
- **Account binding:** Tied to the account that created it. Use a bot/service account.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Digest skips a repo with "Could not retrieve" | Token lacks access to that repo | Update the PAT to include the repo |
| All repos skipped | Token expired or revoked | Generate a new PAT and update the secret |
| `Resource not accessible by integration` | PAT is classic (not fine-grained) | Create a fine-grained PAT instead |
| Digest doesn't run at all | Workflow not on default branch | Ensure `weekly-digest.yml` is on `main` |

## Adding new repos to the digest

When a new repo adopts the changelog pipeline, update the `REPOS` env var in `weekly-digest.yml` to include the new repo name. No token changes needed — the PAT covers all org repos.
