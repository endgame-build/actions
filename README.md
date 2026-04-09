# Actions

Composite GitHub Actions and reusable workflows for the `endgame-build` org.

## Available Actions

### setup-jira

Download, cache, and add `jira-cli` to PATH.

```yaml
- uses: actions/create-github-app-token@v1
  id: app-token
  with:
    app-id: ${{ secrets.JIRA_CLI_APP_ID }}
    private-key: ${{ secrets.JIRA_CLI_APP_PRIVATE_KEY }}
    owner: endgame-build

- uses: endgame-build/actions/setup-jira@v1
  with:
    token: ${{ steps.app-token.outputs.token }}
    # version: '1.2.3'  # optional, defaults to latest
```

#### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `token` | Yes | — | GitHub token with read access to `endgame-build/jira-cli` releases |
| `version` | No | `latest` | Jira CLI version (without `v` prefix) or `"latest"` |

#### Authentication

The recommended approach is a [GitHub App](https://docs.github.com/en/apps) installed on `endgame-build/jira-cli` with **Contents: Read-only** permission. Each consuming repo needs two secrets:

| Secret | Description |
|--------|-------------|
| `JIRA_CLI_APP_ID` | GitHub App ID |
| `JIRA_CLI_APP_PRIVATE_KEY` | GitHub App private key (`.pem`) |

#### Notes

- The GitHub App must be installed on the `endgame-build/jira-cli` repository.
- Binaries are cached by OS, architecture, and version tag — subsequent runs hit cache.
- Supported platforms: Linux and macOS (amd64, arm64).
- For issues, visit the [main repository](https://github.com/endgame-build/jira-cli).

## Reusable Workflows

### AI-Powered Changelog

Generates polished `CHANGELOG.md` entries on every PR merge using [git-cliff](https://github.com/orhun/git-cliff) + Claude AI consensus.

**Quick setup — copy one file:**

```bash
cp templates/on-merge.yml .github/workflows/on-merge.yml
```

**How it works:**
1. PR merges to main
2. git-cliff generates raw changelog entries from conventional commits
3. Three Claude agents analyze the PR (diff, description, commits) via `structured_output`
4. A synthesis agent merges consensus into one clean, user-facing entry
5. A changelog PR is created and assigned to the original author
6. Slack notification posted to team channel (if configured)
7. Author reviews and merges
8. Falls back to raw git-cliff if AI is unavailable

All shell logic in `scripts/` — testable locally with `bash tests/run.sh` (57 tests).

**Required secrets** (per-repo or org-level):

| Secret | Description |
|--------|-------------|
| `CLAUDE_CODE_OAUTH_TOKEN` | From `claude setup-token`. Uses your Claude Team/Pro subscription. |
| `SLACK_BOT_TOKEN` | Slack bot token (`xoxb-`) with `chat:write` scope. Optional — notifications skipped if missing. |
| `CROSS_REPO_READ_TOKEN` | PAT with `contents:read` on tracked repos. Only needed for the weekly digest. |

**Optional repo variables** (Settings > Variables > Actions):

| Variable | Description |
|----------|-------------|
| `SLACK_TEAM_CHANNEL_ID` | Slack channel ID for per-merge notifications. Empty = no notification. |
| `SLACK_PUBLIC_CHANNEL_ID` | Slack channel ID for the weekly digest. |

**Slack setup:**
1. Create a Slack app at [api.slack.com/apps](https://api.slack.com/apps)
2. Add `chat:write` bot scope under OAuth & Permissions
3. Install to workspace, copy the `xoxb-` token
4. Store as `SLACK_BOT_TOKEN` secret
5. Invite the bot to your channels (`/invite @YourBotName`)
6. Get channel IDs: right-click channel name > View channel details > copy ID at bottom
7. Store as repo variables: `SLACK_TEAM_CHANNEL_ID` and/or `SLACK_PUBLIC_CHANNEL_ID`

**Commit categories (from conventional commits):**

| Prefix | Changelog Category |
|--------|-------------------|
| `feat` | Added |
| `fix` | Fixed |
| `docs`, `refactor`, `perf`, `style`, `chore` | Changed |
| `security` | Security |
| `deprecate` | Deprecated |
| `revert` | Changed |
| `test`, `ci`, `build` | Skipped |

**Notifications:**
- **Per-merge (team channel):** Posts the AI-polished changelog entry when a PR merges. Requires `SLACK_TEAM_CHANNEL_ID` variable.
- **Weekly digest (public channel):** Monday 9:00 UTC, aggregates finalized `[Unreleased]` entries from all tracked repos. Requires `SLACK_PUBLIC_CHANNEL_ID` variable and `CROSS_REPO_READ_TOKEN` secret.

**Notes:**
- Bot commits include `[skip ci]` to prevent re-triggering CI/release workflows
- The changelog workflow uses a concurrency group to handle simultaneous merges
- Changelog PRs are labeled `changelog` for easy filtering
- Repos with `push`-triggered workflows should add `if: github.actor != 'github-actions[bot]'` to prevent double-triggering
