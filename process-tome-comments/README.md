# process-tome-comments

Reusable GitHub workflow that turns unresolved review comments in `.tome/comments.jsonl` into pull requests.

## What it does

When a user pushes new comments to `.tome/comments.jsonl` (typically from the [Tome editor](https://github.com/endgame-build/tome)), this workflow:

1. Reads unresolved comments
2. Skips any that already have a PR (any state)
3. Groups remaining comments by `(filePath, blockIndex)` — one cluster per block
4. For each cluster, invokes Claude to apply the requested edits
5. Opens one PR per cluster, with the comment author(s) auto-assigned as reviewers
6. On merge, marks the cluster's comments as resolved in `.tome/comments.jsonl` via a separate bot commit on the default branch

The workflow is capped at 10 open tome-comment PRs at any time to keep reviewer load bounded; it auto-refills as PRs are merged or closed.

## Adoption (one-time, per consumer repo)

### 1. Install the `tome-comments` GitHub App

Visit the App's install page (org admins only). Install on the consumer repo with:
- **Contents: Read & Write**
- **Pull requests: Read & Write**

Don't grant other permissions — they aren't needed.

### 2. Verify org secrets are visible

The workflow reads three org-level secrets:
- `CLAUDE_CODE_OAUTH_TOKEN`
- `TOME_COMMENTS_APP_ID`
- `TOME_COMMENTS_APP_PRIVATE_KEY`

Confirm in **Org Settings → Secrets and variables → Actions** that all three are visible to the consumer repo (selected-repo or all-repo visibility).

### 3. Add the wrapper workflow

Copy `wrapper.example.yml` to the consumer repo's `.github/workflows/process-tome-comments.yml`. ~25 lines, no configuration needed.

### 4. Test

- Add a test comment to `.tome/comments.jsonl` (any markdown file)
- Push to `main`
- Watch the Actions tab; expect one PR opened within ~2 minutes
- Merge the PR; expect a follow-up commit on `main` updating `comments.jsonl`

## How it differs from the human `/process-comments` skill

The interactive `process-comments` skill (at `odevo-hub/.claude/skills/process-comments/SKILL.md` and elsewhere) requires user confirmation via `AskUserQuestion` for every edit. This action:

- Removes all interactive prompts; the agent applies its best edit directly
- Drops the JSONL self-write (a separate listener handles that on PR merge, avoiding merge conflicts between concurrent PRs)
- Constrains the agent's final output to a JSON schema for deterministic PR creation by the workflow

The agent receives the standing instructions inline at the top of its prompt. The instructions live at `process-tome-comments/prompt/prelude.md` and are sparse-checked-out at workflow runtime. This is NOT loaded via Claude Code's skill mechanism — it's plain prompt content concatenated with cluster-specific context by `scripts/build_cluster_prompt.py`.

## Architecture

```
push to .tome/comments.jsonl     ─► prepare ─► process (matrix, max-parallel: 1) ─► PRs
pull_request: closed (merged)    ─► consolidate ─► JSONL update on main ─► refill via process
workflow_dispatch                ─► same as push, with optional max_open_prs override
```

Two modes (`process`, `consolidate`) dispatched by the wrapper based on event type. See the design plan for full details.

## Cost

Empirical (per the spike): ~$0.11/cluster steady-state in Claude API costs. First invocation in a fresh session is ~$0.36 (cold-start). For a repo with 80 unresolved comments adopted from a backlog, total first-batch cost ≈ $9. Steady-state monthly cost at 50 clusters/month ≈ $5–7 per active repo.

## Limits and known issues

- **One PR per cluster.** Multi-approach PRs (multiple substantively different solutions per cluster) are not yet supported. v1 always produces one PR per cluster; reviewers can request alternatives via `@claude` follow-up on the open PR.
- **Cross-block conflicts not auto-handled.** Two PRs touching adjacent block edits that overlap textually merge cleanly individually but conflict against each other. Recovery: GitHub blocks the second merge; reviewer requests `@claude rebase` on the conflicting PR (requires `agent-pr-fix.yml`-style workflow installed).
- **Closed-without-merge PRs are not retried.** If a reviewer closes a PR without merging, the action treats that comment as handled and won't regenerate. Reviewer's escape hatches: resolve in Tome, re-open the closed PR, or `workflow_dispatch` with a force flag (not yet implemented).
- **`pull_request: closed` fires for every PR closed in the repo** (not just tome PRs). The reusable workflow short-circuits if the closed PR has no `tome-comment-id:*` labels — wasted runner boot cost ~10s per non-tome closure.

## Files

```
process-tome-comments/
├── README.md                       # this file
├── prompt/
│   └── prelude.md                  # standing agent instructions (inlined into prompt)
├── schema/
│   └── pr-metadata.schema.json     # JSON schema for agent's structured output
├── scripts/                        # Python 3.10+ (stdlib only); GHA Ubuntu runners have python3 pre-installed
│   ├── _common.py                  # shared helpers (subprocess wrappers, data types)
│   ├── prepare_clusters.py         # cluster + slot computation
│   ├── restore_cluster.py          # rebuild cluster JSON on the per-matrix runner
│   ├── build_cluster_prompt.py     # compose per-cluster agent prompt
│   ├── snapshot_and_pr.py          # validate, branch, push, open PR
│   └── consolidate.py              # post-merge JSONL update
├── wrapper.example.yml             # per-repo workflow file (copy to consumer)
.github/workflows/
└── process-tome-comments.yml       # the reusable workflow
```
