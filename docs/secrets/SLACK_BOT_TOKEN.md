# SLACK_BOT_TOKEN

## What it is

A Slack bot token (`xoxb-`) that lets GitHub Actions post messages to Slack channels. Created from a Slack app with `chat:write` scope.

## Why it's needed

The changelog pipeline posts two types of Slack messages:
1. **Per-merge:** The AI-polished changelog entry posted to the team channel after each PR merge
2. **Weekly digest:** Aggregated unreleased entries from all tracked repos posted to a public channel every Monday

Without this token, Slack notifications are silently skipped. The changelog PR is still created.

## Where to set it

| Scope | When |
|-------|------|
| **Org-level secret** (preferred) | One token for all repos. Same bot, same app. |
| **Per-repo secret** | Set on each repo + on `endgame-build/actions` (for weekly digest) |

## How to create

### Step 1: Create the Slack app from manifest

Go to [api.slack.com/apps](https://api.slack.com/apps) > **Create New App** > **From an app manifest** > select your workspace > paste:

```yaml
_metadata:
  major_version: 1
  minor_version: 1
display_information:
  name: Changelog Bot
  description: Posts AI-refined changelog entries and weekly digests
features:
  bot_user:
    display_name: Changelog Bot
    always_online: false
oauth_config:
  scopes:
    bot:
      - chat:write
settings:
  org_deploy_enabled: false
  socket_mode_enabled: false
  token_rotation_enabled: false
```

### Step 2: Install and get the token

1. After creation, go to **OAuth & Permissions** in the left sidebar
2. Click **Install to Workspace** > **Allow**
3. Copy the **Bot User OAuth Token** (starts with `xoxb-`)

### Step 3: Invite the bot to channels

In each Slack channel that will receive notifications:

```
/invite @Changelog Bot
```

## How to set

**Per-repo:**

```bash
# Paste the xoxb- token when prompted
gh secret set SLACK_BOT_TOKEN --repo endgame-build/<repo-name>
```

**Org-level (requires admin):**

```bash
gh secret set SLACK_BOT_TOKEN --org endgame-build --visibility all
```

**Description for the GitHub settings page:**

> Slack bot token (xoxb-) for the Changelog Bot app. chat:write scope. Posts per-merge entries and weekly digests. See endgame-build/actions/docs/secrets/SLACK_BOT_TOKEN.md.

**Request message for org admin:**

> Need `SLACK_BOT_TOKEN` as an org-level secret for Slack changelog notifications across all repos. It's the xoxb- token from our Changelog Bot Slack app (already created). Go to api.slack.com/apps > Changelog Bot > OAuth & Permissions > copy the Bot User OAuth Token. Then: `gh secret set SLACK_BOT_TOKEN --org endgame-build --visibility all`. Tracked in endgame-build/atelier#149.

## Security

- **Blast radius if leaked:** Attacker can post messages to channels the bot is invited to. No read access to messages, no user data, no admin capabilities.
- **Revocation:** Instant — go to api.slack.com/apps > Changelog Bot > OAuth & Permissions > revoke tokens.
- **Rotation:** Revoke and reinstall the app to generate a new token. Update the secret.
- **Expiry:** Bot tokens do not expire unless manually revoked.

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `not_in_channel` error | Bot not invited to the target channel | Run `/invite @Changelog Bot` in the channel |
| `invalid_auth` error | Token revoked or incorrect | Re-copy from api.slack.com/apps > OAuth & Permissions |
| Messages post but no formatting | Payload structure wrong | Check Block Kit format in the workflow |
| Slack step skipped | `SLACK_TEAM_CHANNEL_ID` variable not set | Set the variable: `gh variable set SLACK_TEAM_CHANNEL_ID --repo ...` |
