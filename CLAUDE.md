# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A collection of **composite GitHub Actions** for the `endgame-build` org. Each action downloads, caches, and adds a CLI tool to `$PATH` in GitHub Actions runners.

Referenced as: `endgame-build/actions/<action-name>@v1`

## Repository Structure

Each action lives in its own directory with an `action.yml` (composite action format). Currently:

- `setup-jira/` — downloads `jira-cli` from private `endgame-build/jira-cli` releases

## Conventions

- **Composite actions** — `runs.using: 'composite'`, no JavaScript/Docker actions. Each action in its own top-level directory.
- **Reusable workflows** — `workflow_call` triggered workflows under `.github/workflows/`. Used for cross-repo automation (changelog, notifications).
- **Caching pattern**: resolve version → detect OS/arch → check `actions/cache@v4` → download on miss → add to `$GITHUB_PATH`.
- **Asset naming**: `<tool>_<tag>_<os>_<arch>.tar.gz` (e.g., `jira_v1.2.3_linux_amd64.tar.gz`).
- **Version input**: accepts `"latest"` (default) or a semver string without `v` prefix. The action normalizes to `v`-prefixed tag internally.
- **Token input**: GitHub PAT with `repo` read access to the private release repo. Passed via `GITHUB_TOKEN` env var for `gh` commands.
- **Cache key format**: `<tool>-<os>-<arch>-<tag>`.
- **Supported platforms**: Linux and macOS, amd64 and arm64.

## Adding a New Action

Create `setup-<tool>/action.yml` following the same pattern as `setup-jira/action.yml`. Update `README.md` with usage and inputs table.

## Changelog Pipeline

The AI-powered changelog pipeline runs on every PR merge in adopting repos. Detailed setup in [README.md](README.md).

### Secrets and Variables

Each secret and variable has its own doc with reasoning, creation instructions, and troubleshooting.

**Secrets** (sensitive — stored encrypted):
- [`CLAUDE_CODE_OAUTH_TOKEN`](docs/secrets/CLAUDE_CODE_OAUTH_TOKEN.md) — Claude AI agents authentication
- [`SLACK_BOT_TOKEN`](docs/secrets/SLACK_BOT_TOKEN.md) — Slack message posting
- [`CROSS_REPO_READ_TOKEN`](docs/secrets/CROSS_REPO_READ_TOKEN.md) — weekly digest cross-repo access

**Variables** (configuration — not sensitive):
- [`SLACK_TEAM_CHANNEL_ID`](docs/variables/SLACK_TEAM_CHANNEL_ID.md) — per-merge notification target
- [`SLACK_PUBLIC_CHANNEL_ID`](docs/variables/SLACK_PUBLIC_CHANNEL_ID.md) — weekly digest target

### Onboarding a new repo

From any repo with the atelier plugin installed, run `/setup-changelog` to verify prerequisites and set up the pipeline.

## Testing

```bash
bash tests/run.sh    # 57 tests across 4 suites, no dependencies
```

Tests use mock `git`/`gh` commands via PATH override. No network, no framework.
