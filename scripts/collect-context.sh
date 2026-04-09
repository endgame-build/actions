#!/usr/bin/env bash
# Collect PR context as GitHub Actions step outputs.
# Requires: PR_NUMBER, GH_TOKEN, GITHUB_OUTPUT env vars.
# Sets 'changed' output to 'true'/'false' based on CHANGELOG.md diff.
#
# Note: outputs are capped at ~50KB each to stay within GitHub Actions'
# 1MB step output limit (4 outputs × ~50KB = ~200KB, well under 1MB).
# This is not silent truncation — it's infrastructure protection.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

MAX_CHARS=50000

if git diff --quiet CHANGELOG.md 2>/dev/null; then
  echo "changed=false" >> "$GITHUB_OUTPUT"
  exit 0
fi
echo "changed=true" >> "$GITHUB_OUTPUT"

output() {
  { echo "$1<<EOF_$1"; echo "$2"; echo "EOF_$1"; } >> "$GITHUB_OUTPUT"
}

output "cliff" "$(git diff CHANGELOG.md 2>/dev/null | head -c $MAX_CHARS || true)"
output "desc" "$(retry 3 gh pr view "$PR_NUMBER" --json body --jq '.body // ""' 2>/dev/null | head -c $MAX_CHARS || true)"
output "diff" "$(git diff --stat HEAD~1 HEAD 2>/dev/null | tail -50 || true)
$(git diff --name-only HEAD~1 HEAD 2>/dev/null | head -100 || true)"
output "commits" "$(retry 3 gh pr view "$PR_NUMBER" --json commits --jq '[.commits[].messageHeadline] | join("; ")' 2>/dev/null | head -c $MAX_CHARS || true)"
