# Changelog

All notable changes to this project are documented in this file.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- Java-audit pipeline with version-adaptive detection and consensus ([#162](https://github.com/endgame-build/atelier/pull/162))
- DevOps-audit pipeline with consensus-based configuration audit ([#136](https://github.com/endgame-build/atelier/pull/136))
- Work-package skill for decomposing feature specs into agent units ([`d87ea85`](https://github.com/endgame-build/atelier/commit/d87ea85))
- Setup-learnings command for CLAUDE.learnings.md tracking ([`b6b069f`](https://github.com/endgame-build/atelier/commit/b6b069f))

### Changed

- Rewrite README with comprehensive architecture documentation ([`dcbfa7b`](https://github.com/endgame-build/atelier/commit/dcbfa7b), [`12f75b1`](https://github.com/endgame-build/atelier/commit/12f75b1), [`a26482a`](https://github.com/endgame-build/atelier/commit/a26482a), [`e7bb85c`](https://github.com/endgame-build/atelier/commit/e7bb85c))
- Consolidate 32 protocol skills into 3 families ([#90](https://github.com/endgame-build/atelier/pull/90))

### Removed

- Ticket-agent moved to separate repository ([`fe08815`](https://github.com/endgame-build/atelier/commit/fe08815))

### Fixed

- Bash 3.2 empty array expansion under set -u in facet-scan ([`e69988d`](https://github.com/endgame-build/atelier/commit/e69988d))
- Skill validation findings in frontend-audit ([#140](https://github.com/endgame-build/atelier/pull/140))
