# SLACK_TEAM_CHANNEL_ID

## What it is

A Slack channel ID (e.g., `C0AL1GBS3M2`) that tells the changelog pipeline where to post per-merge notifications. Stored as a GitHub Actions **variable** (not a secret — channel IDs are not sensitive).

## Why it's needed

After each PR merge, the pipeline posts the AI-polished changelog entry to a team Slack channel. The channel ID tells the workflow which channel to use. Without it, the Slack notification step is silently skipped. The changelog PR is still created.

## Where to set it

| Scope | Where |
|-------|-------|
| **Per-repo variable** | Each repo sets its own — different repos may post to different channels |

This is NOT set at org-level because the target channel may differ per repo.

## How to get the channel ID

### Option A: Slack UI

1. Open Slack
2. Right-click the target channel name
3. Click **View channel details**
4. Scroll to the bottom — the channel ID is at the bottom of the dialog (e.g., `C0AL1GBS3M2`)
5. Copy it

### Option B: Slack API

```bash
# Requires SLACK_BOT_TOKEN
curl -s -H "Authorization: Bearer xoxb-YOUR-TOKEN" \
  "https://slack.com/api/conversations.list?types=public_channel,private_channel&limit=200" \
  | jq -r '.channels[] | select(.name == "the-engine-room") | .id'
```

## How to set

```bash
gh variable set SLACK_TEAM_CHANNEL_ID --repo endgame-build/<repo-name> --body "C0AL1GBS3M2"
```

**Description for the GitHub settings page:**

> Slack channel ID for per-merge changelog notifications. The AI-polished entry is posted here after each PR merge. Not sensitive — just an identifier.

## Security

Not sensitive. Channel IDs are visible to all workspace members. Stored as a variable (visible in repo settings), not a secret.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Slack notification skipped | Variable not set or empty | `gh variable set SLACK_TEAM_CHANNEL_ID --repo ...` |
| `channel_not_found` error | Wrong channel ID or channel deleted | Verify the ID in Slack channel details |
| `not_in_channel` error | Bot not invited to the channel | `/invite @Changelog Bot` in the channel |
