#!/usr/bin/env bash
# Collect PR context as GitHub Actions step outputs.
# Requires: PR_NUMBER, GH_TOKEN, GITHUB_OUTPUT env vars.
# Sets 'changed' output to 'true'/'false' based on CHANGELOG.md diff.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

if git diff --quiet CHANGELOG.md 2>/dev/null; then
  echo "changed=false" >> "$GITHUB_OUTPUT"
  exit 0
fi
echo "changed=true" >> "$GITHUB_OUTPUT"

output() {
  { echo "$1<<EOF_$1"; echo "$2"; echo "EOF_$1"; } >> "$GITHUB_OUTPUT"
}

output "cliff" "$(git diff CHANGELOG.md 2>/dev/null | head -c 4000 || true)"
output "desc" "$(retry 3 gh pr view "$PR_NUMBER" --json body --jq '.body // ""' 2>/dev/null | head -c 2000 || true)"
output "diff" "$(git diff --stat HEAD~1 HEAD 2>/dev/null | tail -20 || true)
$(git diff --name-only HEAD~1 HEAD 2>/dev/null | head -30 || true)"
output "commits" "$(retry 3 gh pr view "$PR_NUMBER" --json commits --jq '[.commits[].messageHeadline] | join("; ")' 2>/dev/null | head -c 1500 || true)"
