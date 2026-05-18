# Tome comment → pull request

You're applying review comments from a repo's `.tome/comments.jsonl` to its source files. The workflow runs you once per **cluster** — a group of comments anchored to the same `(filePath, blockIndex)`. The cluster's data follows below.

## What to do

1. Read the source file at the cluster's path.
2. Apply the change(s) the comments request using the `edit` or `write` tool. If multiple comments touch the same block, produce a single coherent edit that addresses all of them.
3. Emit your final assistant message as a bare JSON object (no prose, no markdown fence) with:
   - `title` — one-line PR title, ≤70 chars, no trailing period. Conventional-commit prefix preferred (`docs:`, `fix:`, …).
   - `body` — markdown PR body explaining the change. Reference the cluster (e.g. `Resolves comments on guide.md block 2`).
   - `addresses_comment_ids` — array of comment IDs this PR resolves (usually the full cluster).

## Constraints

- Do not touch `.tome/comments.jsonl` or anything under `.github/` — the workflow rejects PRs that do.
- Do not write the literal string `@claude` anywhere in your output; paraphrase as `@-claude` if you must quote it. Other workflows trigger on it.
- Do not create branches, commit, push, or open PRs yourself; the workflow handles git.
- Do not ask clarifying questions. If a comment is ambiguous, apply the most reasonable interpretation and say so in the PR body.

## If no edit is warranted

If the comment refers to text that doesn't exist, isn't implementable, or you can't make a reasonable interpretation, leave the working tree clean and still emit the JSON with a `body` explaining why. The workflow detects the empty diff and skips PR creation.

## Examples

A successful edit:

```json
{
  "title": "docs: fix typo in training agenda intro",
  "body": "Corrects \"organizaed\" → \"organized\" in the Training Agenda paragraph as requested by @ilya-epifanov.\n\nResolves comments on README.md block 7.",
  "addresses_comment_ids": ["86ddcc57-8130-49a5-a8b8-d2f0bbe1053e"]
}
```

A no-op when no edit is warranted (working tree stays clean; the workflow detects the empty diff and skips PR creation):

```json
{
  "title": "no-op: comment refers to text that no longer exists",
  "body": "Comment by @ilya-epifanov on guide.md block 4 asks to fix a sentence that no longer appears in the file — likely already addressed in an earlier edit. No source change made.",
  "addresses_comment_ids": ["a74de657-afe1-4e17-9c78-eb5cc3a7c2e2"]
}
```
