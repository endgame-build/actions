# Context: process-tome-comments

Domain vocabulary for the `process-tome-comments` reusable workflow. Use these terms exactly in code, comments, and PR discussion. Architecture vocabulary (module, interface, seam, depth) lives in the project's `LANGUAGE.md`; this file is about *what* the system models, not *how* the code is organised.

## Core concepts

**Comment** — one entry in a repo's `.tome/comments.jsonl`, written by the [Tome](https://github.com/endgame-build/tome) editor. A review annotation anchored to a markdown file at a `(filePath, blockIndex)` pair. Has an author, a body, a created-at timestamp, and an `isResolved` flag. Defined in `comments.py:Comment`.

**Cluster** — a group of unresolved comments sharing the same `(filePath, blockIndex)`. The unit of agent invocation: one cluster → one agent call → one PR. Defined in `comments.py:Cluster`. A cluster's identity is its **latest comment id** (most-recent `createdAt`); used for branch naming and the PR's headline label.

**Prelude** — the standing instructions inlined into every per-cluster agent prompt. Lives at `prompt/prelude.md`. Describes the two required actions (apply edits, emit JSON metadata), tool semantics, forbidden modifications, and unactionable-comment fallback. The prelude is **identical across clusters**; per-cluster context is appended at runtime.

**PR metadata** — the constrained JSON the agent emits as its final assistant message: `{title, body, addresses_comment_ids}`. Defined in `metadata.py:Metadata`. Validated post-hoc against `schema/pr-metadata.schema.json` by `metadata.py:validate_metadata`. The workflow uses this metadata (not the agent's git operations) to package the PR.

**PR plan** — the validated, sanitised, ready-to-submit PR shape derived from a cluster + the agent's raw assistant text. Defined in `pr_plan.py:PRPlan`. Pure: `PRPlan.build(cluster, agent_text)` parses the PR metadata, sanitises the `@claude` mention, truncates the title to 70 chars, derives labels from comment ids, and derives reviewers from cluster authors. The submission step consumes a `PRPlan` and does I/O only — it never re-derives these fields.

**Idempotency filter** — the pre-cluster check that drops any comment whose `id` already has an associated PR (any state). Prevents re-processing comments that have been handled, and prevents looping on comments the reviewer chose to close without merging (Q2 safety net). Implemented via `TomeBacklog`: a single `gh pr list` call returns every tome-PR's labels, the comment ids are extracted from `tome-comment-id:<uuid>` labels, and the filter becomes an in-memory set lookup.

**Tome backlog** — snapshot of the repo's current tome-PR state, built once per `prepare` invocation. Defined in `backlog.py:TomeBacklog`. Carries the set of comment ids ever addressed (from `tome-comment-id:*` labels across all states) and the count of currently-open tome-PRs. Answers both questions `prepare` asks the GitHub API today (idempotency + slot budget) from one fetch. The single fetch is enabled by the **common tome-PR label** below.

**`auto:tome-comment-pr`** — the common label applied to every tome-PR at open time. Enables the single `label:"auto:tome-comment-pr"` search that powers `TomeBacklog`. `consolidate` removes this label after a successful post-merge push so the scan stays bounded by closed-without-merge volume rather than total lifetime tome-PRs. The per-id `tome-comment-id:*` labels stay forever — they encode which comment ids each PR addressed and are still needed by `consolidate` for the label-to-ids decode.

**Disallowed paths** — paths the agent must not modify. Currently `.github/`, `.tome/comments.jsonl`, `Taskfile.yml`, and `scripts/`. Enforced post-edit by `policy.py:policy_violations`, which runs `git diff --cached --name-only` and returns any matching paths. If non-empty, the cluster is aborted and the working tree restored.

**Pi agent** — the "address one cluster via pi-coding-agent inside nono" abstraction. Defined in `pi_agent.py:PiAgent`. Owns pi provider config (`~/.pi/agent/{models,settings}.json`), prompt assembly, the nono+pi subprocess, and `--mode json` event-stream parsing. Constructed once per job with model id + nono profile path + prelude text; `address(cluster)` returns an `AgentResult` or raises `AgentError` (with the raw `PiInvocation` attached when failure happens post-subprocess, so forensics can still be persisted).

**Bot session** — the `tome-comments[bot]` identity bound to one repo, with git+gh helpers wired in. Defined in `bot.py:BotSession`. Constructing a session resolves the bot login from the App slug, looks up the noreply email, and applies `git config user.{name,email}` — so callers can't accidentally commit under the runner's default identity. Exposes `commit`, `push`, `gh`, and `default_branch` with identity+repo already threaded.

## Modes

The reusable workflow runs in one of two modes, dispatched by the wrapper's `inputs.mode`:

**Process mode** — entered on `push` (to `.tome/comments.jsonl`) and `workflow_dispatch`. Loads unresolved comments, applies the idempotency filter, clusters them, computes the slot budget, and opens one PR per cluster (up to `max_open_prs`).

**Consolidate mode** — entered on `pull_request: closed`. If the closed PR was merged and carries `tome-comment-id:*` labels, marks those comments `isResolved: true` in `.tome/comments.jsonl` on the default branch via a separate bot commit. PR diffs themselves never touch `.tome/`.

## Identities

**`tome-comments[bot]`** — the GitHub App identity that pushes branches, opens PRs, and writes the post-merge consolidate commit. Minted per-job from `TOME_COMMENTS_APP_ID` + `TOME_COMMENTS_APP_PRIVATE_KEY`. The App's slug must resolve to exactly `tome-comments[bot]` (a runtime sanity check fails the workflow otherwise).

**Consumer repo** — the repository that adopts the workflow by adding the wrapper file. The agent runs against a fresh checkout of this repo. App must be installed on it.

**Actions repo** — `endgame-build/actions`, where this workflow lives. Sparse-checked-out into `.actions/` at runtime so consumer repos pick up scripts + prelude + schema + nono profile without having to commit anything but the wrapper.

## Slot budget

**`max_open_prs`** — hard cap on open PRs carrying the `auto:tome-comment-pr` label per repo. Default 10. Auto-refilled on every `pull_request: closed`: the workflow counts open tome PRs (via `TomeBacklog`), subtracts from the cap, and processes that many clusters per run. Sequential (`max-parallel: 1`) so the slot count stays accurate.

## Sandbox

**Profile** — `profiles/pi.json`. A [nono](https://nono.sh/) configuration that confines the agent process: filesystem to workdir + `~/.pi`, network egress to `ollama.com` only (via `network_profile: "minimal"` + `allow_domain`), environment to a small allowlist including `OLLAMA_API_KEY`. The sandbox is unconditional — there is no opt-out.

## Out of scope (v1)

- **Multi-approach PRs** — the original design allowed N PRs per cluster when the agent saw substantively different solutions. Deferred; v1 always produces one PR per cluster.
- **Cross-block conflicts** — comments on adjacent blockIndexes whose edits overlap textually produce two PRs that conflict at merge. Recovery falls through to GitHub's merge-block plus a reviewer-driven `@claude rebase` (requires `agent-pr-fix.yml`-style workflow on the consumer repo).
- **Comment-was-wrong signal** — beyond the idempotency-filter safety net (closed PRs prevent regeneration), the canonical way for a reviewer to reject a comment is to resolve it in Tome.
