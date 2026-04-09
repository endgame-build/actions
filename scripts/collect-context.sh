#!/usr/bin/env bash
# Collect PR context as GitHub Actions step outputs.
# Usage: source this script in a workflow run step.
# Requires: PR_NUMBER env var, GH_TOKEN env var, GITHUB_OUTPUT env var.
set -eu

output() { # name, content
  { echo "$1<<EOF_$1"; echo "$2"; echo "EOF_$1"; } >> "$GITHUB_OUTPUT"
}

output "cliff" "$(git diff CHANGELOG.md 2>/dev/null | head -c 4000)"

output "desc" "$(gh pr view "$PR_NUMBER" --json body --jq '.body // "No description"' 2>/dev/null | head -c 2000 || echo "No description")"

MERGE_BASE=$(git merge-base HEAD~1 HEAD 2>/dev/null || echo "HEAD~1")
DIFF_SUMMARY=$(git diff --stat "$MERGE_BASE" HEAD 2>/dev/null | tail -20)
KEY_FILES=$(git diff --name-only "$MERGE_BASE" HEAD 2>/dev/null | grep -v "^test\|^\.idea\|^\.git\|\.lock$" | head -30)
DIFF_SAMPLE=$(git diff "$MERGE_BASE" HEAD -- '*.md' 'README*' 'CLAUDE*' 2>/dev/null | head -c 4000)
output "diff" "$(printf 'Files changed:\n%s\n\nKey files:\n%s\n\nDiff sample:\n%s' "$DIFF_SUMMARY" "$KEY_FILES" "$DIFF_SAMPLE")"

output "commits" "$(gh pr view "$PR_NUMBER" --json commits --jq '.commits[].messageHeadline' 2>/dev/null | head -c 1500 || echo "Commits unavailable")"
