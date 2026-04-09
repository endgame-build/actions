#!/usr/bin/env bash
# Collect PR context as GitHub Actions step outputs.
# Requires: PR_NUMBER, GH_TOKEN, GITHUB_OUTPUT env vars.
set -eu

output() {
  { echo "$1<<EOF_$1"; echo "$2"; echo "EOF_$1"; } >> "$GITHUB_OUTPUT"
}

output "cliff" "$(git diff CHANGELOG.md 2>/dev/null | head -c 4000 || true)"

output "desc" "$(gh pr view "$PR_NUMBER" --json body --jq '.body // ""' 2>/dev/null | head -c 2000 || true)"

output "diff" "$(git diff --stat HEAD~1 HEAD 2>/dev/null | tail -20 || true)
$(git diff --name-only HEAD~1 HEAD 2>/dev/null | head -30 || true)"

output "commits" "$(gh pr view "$PR_NUMBER" --json commits --jq '[.commits[].messageHeadline] | join("; ")' 2>/dev/null | head -c 1500 || true)"
