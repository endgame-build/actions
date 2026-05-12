# Context: process-tome-comments

Domain vocabulary for the `process-tome-comments` reusable workflow. Use these terms exactly in code, comments, and PR discussion. Architecture vocabulary (module, interface, seam, depth) lives in the project's `LANGUAGE.md`; this file is about *what* the system models, not *how* the code is organised.

## Core concepts

**Comment** — one entry in a repo's `.tome/comments.jsonl`, written by the [Tome](https://github.com/endgame-build/tome) editor. A review annotation anchored to a markdown file at a `(filePath, blockIndex)` pair. Has an author, a body, a created-at timestamp, and an `isResolved` flag. Defined in `_common.py:Comment`.

**Cluster** — a group of unresolved comments sharing the same `(filePath, blockIndex)`. The unit of agent invocation: one cluster → one agent call → one PR. Defined in `_common.py:Cluster`. A cluster's identity is its **latest comment id** (most-recent `createdAt`); used for branch naming and the PR's headline label.

**Prelude** — the standing instructions inlined into every per-cluster agent prompt. Lives at `prompt/prelude.md`. Describes the two required actions (apply edits, emit JSON metadata), tool semantics, forbidden modifications, and unactionable-comment fallback. The prelude is **identical across clusters**; per-cluster context is appended at runtime.

**PR metadata** — the constrained JSON the agent emits as its final assistant message: `{title, body, addresses_comment_ids}`. Validated post-hoc by `snapshot_and_pr` against `schema/pr-metadata.schema.json`. The workflow uses this metadata (not the agent's git operations) to package the PR.

**Idempotency filter** — the pre-cluster check that drops any comment whose `id` already has an associated PR (any state) carrying the `tome-comment-id:<uuid>` label. Prevents re-processing comments that have been handled, and prevents looping on comments the reviewer chose to close without merging (Q2 safety net).

**Disallowed paths** — paths the agent must not modify. Currently `.github/`, `.tome/comments.jsonl`, `Taskfile.yml`, and `scripts/`. Enforced post-edit by inspecting `git diff --cached --name-only` against `DISALLOWED_PATH_RE`. If matched, the cluster is aborted and the working tree restored.

## Modes

The reusable workflow runs in one of two modes, dispatched by the wrapper's `inputs.mode`:

**Process mode** — entered on `push` (to `.tome/comments.jsonl`) and `workflow_dispatch`. Loads unresolved comments, applies the idempotency filter, clusters them, computes the slot budget, and opens one PR per cluster (up to `max_open_prs`).

**Consolidate mode** — entered on `pull_request: closed`. If the closed PR was merged and carries `tome-comment-id:*` labels, marks those comments `isResolved: true` in `.tome/comments.jsonl` on the default branch via a separate bot commit. PR diffs themselves never touch `.tome/`.

## Identities

**`tome-comments[bot]`** — the GitHub App identity that pushes branches, opens PRs, and writes the post-merge consolidate commit. Minted per-job from `TOME_COMMENTS_APP_ID` + `TOME_COMMENTS_APP_PRIVATE_KEY`. The App's slug must resolve to exactly `tome-comments[bot]` (a runtime sanity check fails the workflow otherwise).

**Consumer repo** — the repository that adopts the workflow by adding the wrapper file. The agent runs against a fresh checkout of this repo. App must be installed on it.

**Actions repo** — `endgame-build/actions`, where this workflow lives. Sparse-checked-out into `.actions/` at runtime so consumer repos pick up scripts + prelude + schema + nono profile without having to commit anything but the wrapper.

## Slot budget

**`max_open_prs`** — hard cap on open PRs labeled `tome-comment-id:*` per repo. Default 10. Auto-refilled on every `pull_request: closed`: the workflow counts open tome PRs, subtracts from the cap, and processes that many clusters per run. Sequential (`max-parallel: 1`) so the slot count stays accurate.

## Sandbox

**Profile** — `profiles/pi.json`. A [nono](https://nono.sh/) configuration that confines the agent process: filesystem to workdir + `~/.pi`, network egress to `ollama.com` only (via `network_profile: "minimal"` + `allow_domain`), environment to a small allowlist including `OLLAMA_API_KEY`. The sandbox is unconditional — there is no opt-out.

## Out of scope (v1)

- **Multi-approach PRs** — the original design allowed N PRs per cluster when the agent saw substantively different solutions. Deferred; v1 always produces one PR per cluster.
- **Cross-block conflicts** — comments on adjacent blockIndexes whose edits overlap textually produce two PRs that conflict at merge. Recovery falls through to GitHub's merge-block plus a reviewer-driven `@claude rebase` (requires `agent-pr-fix.yml`-style workflow on the consumer repo).
- **Comment-was-wrong signal** — beyond the idempotency-filter safety net (closed PRs prevent regeneration), the canonical way for a reviewer to reject a comment is to resolve it in Tome.
