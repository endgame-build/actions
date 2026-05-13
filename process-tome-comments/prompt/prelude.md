# Process Tome Comments (CI)

Apply unresolved review comments from `.tome/comments.jsonl` to the source file and emit PR metadata for the workflow to package as a pull request.

This prelude is the standing instructions for the `process-tome-comments` GitHub Action. It is concatenated with cluster-specific context to form the prompt for each per-cluster agent invocation. Each invocation handles one cluster of comments anchored to the same `(filePath, blockIndex)`.

## Two required actions

Both are mandatory; the JSON output is enforced by `--json-schema`.

### ACTION A — Apply the edit

1. Read the cluster of comments from `.tome/comments.jsonl`. The cluster's comment IDs are provided in the prompt as `CLUSTER_COMMENT_IDS`. Each cluster member shares the same `filePath` and `blockIndex`.
2. Read the source file at the cluster's `filePath`.
3. Identify the change(s) the comments collectively request. If multiple comments touch the same block, produce a single coherent edit that addresses all of them. Apply edits in arrival order (earliest `createdAt` first) when their requests stack.
4. Apply the change(s) using the `edit` or `write` tool. Be thorough: if a comment says "rename X to Y everywhere", apply it to every occurrence in the file.

**Tool semantics:** the `edit` tool requires each `oldText` to occur exactly once in the file — include enough surrounding context to disambiguate. For a "rename X to Y everywhere" comment with multiple occurrences, either: (a) call `edit` once per occurrence with a unique surrounding-context oldText, or (b) call `write` to rewrite the whole file. Prefer (a) for small files; (b) for sweeping changes that touch many lines.

### ACTION B — Emit the PR metadata JSON

Your final assistant message MUST be a bare JSON object conforming to the schema. No prose, no markdown fence, no narration. Fields:

- `title` — one-line PR title summarizing the edit. ≤70 chars. No trailing period. Conventional-commit prefix optional but recommended (e.g. `docs:`, `chore:`).
- `body` — markdown PR body explaining what changed and why. Reference the comment authors and the cluster's intent. Include block reference (e.g. `Resolves comments on guide.md block 2`).
- `addresses_comment_ids` — array of comment IDs this PR resolves. Typically equals the full cluster.

## Forbidden

- **Do not** modify `.tome/comments.jsonl`. The post-merge listener owns resolution write-back.
- **Do not** modify `.github/`, `Taskfile.yml`, or any CI configuration. The workflow rejects PRs touching these paths.
- **Do not** include the literal string `@claude` in `title`, `body`, or any output. If quoting a comment that mentions it, paraphrase as `the @-claude trigger`. Other workflows in the repo trigger on `contains(comment.body, '@claude')` and would loop.
- **Do not** create branches, commit, push, or open PRs. The workflow handles git/gh.
- **Do not** ask clarifying questions. If a comment is ambiguous, apply the most reasonable interpretation and explain your choice in the PR `body`.
- **Do not** mark comments resolved in any file.

## When a comment is genuinely unactionable

If after reading the source you conclude no meaningful edit is warranted (e.g., the comment refers to text that no longer exists, the request is not implementable, or it is unclear beyond best-effort interpretation):

- Make no changes to the working tree.
- Still emit the JSON, but with a `body` that explains why no edit was made. The workflow detects empty-diff and skips PR creation, leaving the comment unresolved for human triage.

## Reference: comment schema

```json
{
  "id": "uuid",
  "filePath": "path/to/source/file.md",
  "blockIndex": 2,
  "body": "the comment text",
  "authorLogin": "github-username",
  "createdAt": "ISO-8601",
  "isResolved": false
}
```
