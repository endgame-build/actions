# process-tome-comments — spec

Reusable workflow that converts unresolved comments in a repo's `.tome/comments.jsonl` into pull requests.

## Inputs

| Source | Item |
|---|---|
| Repo file | `.tome/comments.jsonl` — one JSON object per line. Written by the Tome editor. |
| Workflow input | `mode` — `process` or `consolidate`. |
| Workflow input | `max_open_prs` — hard cap on open tome-comment PRs (0 = use upstream default `10`). |
| Org secret | `OLLAMA_API_KEY` — for the pi agent invocation against Ollama Cloud. |
| Org secret | `TOME_COMMENTS_APP_ID`, `TOME_COMMENTS_APP_PRIVATE_KEY` — for the `tome-comments[bot]` App that pushes and opens PRs. |
| Repo variable (optional) | `AUTOFIX_MODEL` — Ollama Cloud model id. Defaults to `gpt-oss:120b`. |

## Triggers (set in the per-repo wrapper)

| Event | Mode |
|---|---|
| `push` to default branch on `.tome/comments.jsonl` | `process` |
| `pull_request: closed` | `consolidate`, then `process` (auto-refill) |
| `workflow_dispatch` (with optional `max_open_prs` override) | `process` |

A `concurrency` group `tome-comments-${{ github.repository }}` serializes all runs per repo.

## Behavior — `process` mode

1. **Fetch backlog.** One `gh pr list --search 'label:"auto:tome-comment-pr"' --state all` call returns every tome-PR with its labels and state (`TomeBacklog`).
2. **Filter.** Load `.tome/comments.jsonl`; drop comments where `isResolved == true`, or where the backlog already contains the comment's id (from a `tome-comment-id:<uuid>` label on any tome-PR).
3. **Cluster.** Group remaining comments by `(filePath, blockIndex)`. One PR per cluster.
4. **Slot budget.** `open_count` comes from the backlog (PRs in state `OPEN`). Slots = `max_open_prs − open_count`. Take the oldest `slots` clusters by earliest member's `createdAt`.
5. **Per cluster, in a matrix step (max-parallel: 1):**
   - Mint a `tome-comments[bot]` App installation token.
   - Fresh checkout of the consumer repo at default branch.
   - Run [pi](https://pi.dev/) against Ollama Cloud (provider configured via `.pi/settings.json`, written at runtime by `configure_pi.py`). The agent runs inside [nono](https://nono.sh/) with the profile at `profiles/pi.json` — filesystem confined to the working tree + `~/.pi`, network confined to `ollama.com`, only `OLLAMA_API_KEY` passed through. The App token is **not** in the agent step's env (it's only in the snapshot step), so a hostile git/gh invocation can't reach GitHub even if it bypassed the sandbox. Pi has no native schema enforcement, so the prompt asks for a JSON object matching `schema/pr-metadata.schema.json` and `snapshot_and_pr.py` post-hoc extracts the first balanced `{…}` from the agent's final message and validates it.
   - Validate: JSON conforms; staged diff is non-empty; no disallowed paths touched (`.github/`, `.tome/comments.jsonl`, `Taskfile.yml`, `scripts/`); strip `@claude` → `@-claude` from title/body.
   - Branch as `tome-comment/<latest-comment-uuid>`, commit with the agent's title as subject, push via the App token.
   - Open PR with labels `auto:tome-comment-pr` (common) + `tome-comment-id:<uuid>` (one per addressed comment) and reviewers = union of comment authors.

## Behavior — `consolidate` mode

Triggered by `pull_request: closed`. If the closed PR is merged AND carries any `tome-comment-id:*` labels:

1. Update `.tome/comments.jsonl` on the default branch: for each addressed comment, set `isResolved: true`, `resolvedBy: tome-comments[bot]`, `resolvedAt: <now>`.
2. Push as a separate bot commit (`chore(tome): resolve comment <shortid>`).
3. After the push succeeds, remove the `auto:tome-comment-pr` label from the PR (best-effort — a failed drop leaves an orphan label but doesn't break idempotency, which now flows through the resolved jsonl entry). Per-id `tome-comment-id:*` labels stay as the historical record and are still what `consolidate` reads to decode which comments to resolve.

PR diffs themselves never touch `.tome/`. Closed-but-not-merged PRs are not processed (the `tome-comment-id` labels on a closed PR keep the comment in the backlog's `addressed_comment_ids`, preventing re-runs from regenerating the same PR).

## Failure handling

- **Per-cluster content failure** (invalid JSON, empty diff, disallowed paths, permanent auth): log, clean working tree, continue to next cluster. Cluster's comments remain unresolved; next trigger retries.
- **Transient API failure** (5xx, 429, network): the SDK's internal retries apply; if exhausted, the matrix step fails (`fail-fast: false`); next trigger retries.
- **Job timeout:** `timeout-minutes: 30` per job.

## Layout

```
process-tome-comments/
├── CONTEXT.md                      # domain vocabulary (Comment, Cluster, prelude, modes, …)
├── README.md                       # this spec
├── prompt/prelude.md               # standing agent instructions (inlined verbatim into each prompt)
├── schema/pr-metadata.schema.json  # documents the agent's JSON output shape
├── profiles/pi.json                # nono profile: workdir + ~/.pi r+w, network to ollama.com only
├── src/process_tome_comments/      # Python 3.11+, stdlib only
│   ├── __main__.py                 # subcommand dispatcher (`python -m process_tome_comments <name>`)
│   ├── comments.py                 # Comment + Cluster types, JSONL I/O, clustering
│   ├── metadata.py                 # PR-metadata JSON extraction + validation (pure)
│   ├── pr_plan.py                  # PRPlan: pure (Cluster, agent_text) → ready-to-submit shape
│   ├── pi_agent.py                 # PiAgent: pi config + prompt + nono+pi subprocess + event parse
│   ├── bot.py                      # BotSession: App-bot identity bound to a repo, git+gh helpers
│   ├── backlog.py                  # TomeBacklog: one-call snapshot of tome-PR state (idempotency + slot count)
│   ├── policy.py                   # post-edit policy check (staged diff vs disallowed paths)
│   ├── gha.py                      # GitHub Actions glue (outputs, log levels, subprocess)
│   ├── prepare.py                  # `prepare` subcommand
│   ├── agent.py                    # `agent` subcommand: thin orchestrator over PiAgent
│   ├── pr_open.py                  # `pr-open` subcommand: PRPlan + policy + BotSession
│   └── consolidate.py              # `consolidate` subcommand: BotSession + JSONL update
└── wrapper.example.yml             # per-repo workflow file (copy verbatim, ~25 lines)

tome-comments-setup/action.yml      # composite action: mint App token + dual checkout
.github/workflows/process-tome-comments.yml  # the reusable workflow
```

## Out of scope (v1)

- Multi-approach PRs per cluster (one PR per cluster always).
- Cross-block edit conflicts (relies on GitHub's merge-block + reviewer-driven `@claude rebase`).
- A "comment is unactionable" signal beyond the closed-PR-label safety net (resolve in Tome is the canonical reject).

## Sandbox

The agent always runs inside [nono](https://nono.sh/) with the profile at `profiles/pi.json`. The kernel-level boundary (Linux Landlock) enforces:

- **Filesystem:** read+write the consumer repo's working tree (`$WORKDIR`) and `~/.pi` only.
- **Network:** outbound HTTP/HTTPS to `ollama.com` only — exfiltration to other hosts is blocked at the egress point.
- **Environment:** only `OLLAMA_API_KEY` (+ a handful of operational vars) is passed through; other secrets in the runner env are not visible to the agent.

GHA Ubuntu runners ship a Landlock-capable kernel (5.13+); first-run failures will most likely surface as denied filesystem reads to paths the profile didn't anticipate. Iterate by extending `filesystem.allow` in `profiles/pi.json`.
