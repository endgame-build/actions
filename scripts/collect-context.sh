#!/usr/bin/env bash
# Collect PR context as GitHub Actions step outputs.
# Requires: PR_NUMBER, GH_TOKEN, GITHUB_OUTPUT env vars.
# Sets 'changed' output to 'true'/'false' based on CHANGELOG.md diff.
#
# Outputs are capped at 50KB each to stay within GitHub Actions'
# 1MB step output limit. If content exceeds the cap, a warning is
# printed and the output is truncated — never silently.
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
output "diff" "$(git diff --stat HEAD~1 HEAD 2>/dev/null | tail -50 || true)
$(git diff --name-only HEAD~1 HEAD 2>/dev/null | head -100 || true)"
output "commits" "$(retry 3 gh pr view "$PR_NUMBER" --json commits --jq '[.commits[].messageHeadline] | join("; ")' 2>/dev/null || true)"
