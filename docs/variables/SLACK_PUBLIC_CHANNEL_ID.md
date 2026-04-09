# SLACK_PUBLIC_CHANNEL_ID

## What it is

A Slack channel ID (e.g., `C0ARC40L8KX`) for the weekly changelog digest. The Monday morning summary of all unreleased changes across tracked repos is posted here. Stored as a GitHub Actions **variable** (not a secret).

## Why it's needed

The weekly digest aggregates `[Unreleased]` entries from all repos' `CHANGELOG.md` files and posts a formatted summary to a public Slack channel. This gives wider stakeholders visibility into what shipped without watching every repo.

Without it, the weekly digest workflow skips the Slack post. No error — just no notification.

## Where to set it

| Scope | Where |
|-------|-------|
| **Variable on `endgame-build/actions`** | The weekly digest workflow runs here |

Only needed on the actions repo. Spoke repos do not need this variable.

## How to get the channel ID

### Option A: Slack UI

1. Open Slack
2. Right-click the public channel name
3. Click **View channel details**
4. Scroll to the bottom — copy the channel ID

### Option B: Slack API

```bash
curl -s -H "Authorization: Bearer xoxb-YOUR-TOKEN" \
  "https://slack.com/api/conversations.list?types=public_channel&limit=200" \
  | jq -r '.channels[] | select(.name == "your-channel-name") | .id'
```

## How to set

```bash
gh variable set SLACK_PUBLIC_CHANNEL_ID --repo endgame-build/actions --body "C0ARC40L8KX"
```

**Description for the GitHub settings page:**

> Slack channel ID for the weekly changelog digest. Monday 9:00 UTC summary of unreleased changes across all tracked repos. Not sensitive.

## Security

Not sensitive. Channel IDs are visible to all workspace members.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Digest runs but no Slack message | Variable not set or empty | `gh variable set SLACK_PUBLIC_CHANNEL_ID --repo endgame-build/actions` |
| `channel_not_found` error | Wrong channel ID | Verify the ID in Slack channel details |
| `not_in_channel` error | Bot not invited | `/invite @Changelog Bot` in the channel |
| Digest doesn't run | Cron schedule only fires on default branch | Ensure `weekly-digest.yml` is on `main` |
