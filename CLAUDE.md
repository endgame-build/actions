# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

GitHub Actions and reusable workflows for the `endgame-build` org. Two flavors:

1. **Single-purpose composite actions** — one directory at the repo root, named `setup-<tool>/`. Downloads, caches, and adds a CLI tool to `$PATH`. Referenced as `endgame-build/actions/setup-<tool>@v1`. Example: `setup-jira/`.

2. **Multi-component features** — a top-level feature directory holding everything for that feature except the workflow file (which GitHub requires under `.github/workflows/`). Composite preambles nest under `<feature>/setup/action.yml` and are referenced as `endgame-build/actions/<feature>/setup@v1`. Example: `process-tome-comments/` + `.github/workflows/process-tome-comments.yml`.

## Conventions for `setup-<tool>` actions

- **Composite actions only** — `runs.using: 'composite'`, no JavaScript/Docker actions.
- **Caching pattern**: resolve version → detect OS/arch → check `actions/cache@v4` → download on miss → add to `$GITHUB_PATH`.
- **Asset naming**: `<tool>_<tag>_<os>_<arch>.tar.gz` (e.g., `jira_v1.2.3_linux_amd64.tar.gz`).
- **Version input**: accepts `"latest"` (default) or a semver string without `v` prefix. The action normalizes to `v`-prefixed tag internally.
- **Token input**: GitHub PAT with `repo` read access to the private release repo. Passed via `GITHUB_TOKEN` env var for `gh` commands.
- **Cache key format**: `<tool>-<os>-<arch>-<tag>`.
- **Supported platforms**: Linux and macOS, amd64 and arm64.

## Adding new automation

- Simple CLI-tool installer: create `setup-<tool>/action.yml` following `setup-jira/`. Update `README.md`.
- Multi-component feature: see `process-tome-comments/README.md` for the layout reference.

## No build/test/lint

YAML and (per-feature) Python only. No build step, test suite, or linter configured at the repo level. Multi-component features may declare Python deps in `<feature>/requirements.txt`, installed at runtime by the workflow.
