#!/usr/bin/env bash
# Collect PR context as GitHub Actions step outputs.
# Requires: PR_NUMBER, GH_TOKEN, GITHUB_OUTPUT env vars.
# Sets 'changed' output to 'true'/'false' based on CHANGELOG.md diff.
#
# GitHub Actions limit: 1MB total per job for all step outputs combined.
# (Source: https://docs.github.com/en/actions/reference/limits)
# With 4 output fields, each field is capped at 200KB to stay under 1MB.
# If content exceeds the cap, a warning is printed — never silent.
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

MAX_CHARS=200000  # 200KB per field × 4 fields = 800KB < 1MB job limit

if git diff --quiet CHANGELOG.md 2>/dev/null; then
  echo "changed=false" >> "$GITHUB_OUTPUT"
  exit 0
fi
echo "changed=true" >> "$GITHUB_OUTPUT"

output() {
  local name="$1" content="$2"
  local length=${#content}
  if [ "$length" -gt "$MAX_CHARS" ]; then
    echo "WARNING: $name output truncated from ${length} to ${MAX_CHARS} chars" >&2
    content="${content:0:$MAX_CHARS}"
  fi
  { echo "$name<<EOF_$name"; echo "$content"; echo "EOF_$name"; } >> "$GITHUB_OUTPUT"
}

output "cliff" "$(git diff CHANGELOG.md 2>/dev/null || true)"
output "desc" "$(retry 3 gh pr view "$PR_NUMBER" --json body --jq '.body // ""' 2>/dev/null || true)"
output "diff" "$(git diff --stat HEAD~1 HEAD 2>/dev/null || true)
$(git diff --name-only HEAD~1 HEAD 2>/dev/null || true)"
output "commits" "$(retry 3 gh pr view "$PR_NUMBER" --json commits --jq '[.commits[].messageHeadline] | join("; ")' 2>/dev/null || true)"
