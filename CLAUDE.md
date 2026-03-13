# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A collection of **composite GitHub Actions** for the `endgame-build` org. Each action downloads, caches, and adds a CLI tool to `$PATH` in GitHub Actions runners.

Referenced as: `endgame-build/actions/<action-name>@v1`

## Repository Structure

Each action lives in its own directory with an `action.yml` (composite action format). Currently:

- `setup-jira/` — downloads `jira-cli` from private `endgame-build/jira-cli` releases

## Conventions

- **Composite actions only** — `runs.using: 'composite'`, no JavaScript/Docker actions.
- **Caching pattern**: resolve version → detect OS/arch → check `actions/cache@v4` → download on miss → add to `$GITHUB_PATH`.
- **Asset naming**: `<tool>_<tag>_<os>_<arch>.tar.gz` (e.g., `jira_v1.2.3_linux_amd64.tar.gz`).
- **Version input**: accepts `"latest"` (default) or a semver string without `v` prefix. The action normalizes to `v`-prefixed tag internally.
- **Token input**: GitHub PAT with `repo` read access to the private release repo. Passed via `GITHUB_TOKEN` env var for `gh` commands.
- **Cache key format**: `<tool>-<os>-<arch>-<tag>`.
- **Supported platforms**: Linux and macOS, amd64 and arm64.

## Adding a New Action

Create `setup-<tool>/action.yml` following the same pattern as `setup-jira/action.yml`. Update `README.md` with usage and inputs table.

## No Build/Test/Lint

There is no build step, test suite, or linter configured. Actions are YAML-only.
