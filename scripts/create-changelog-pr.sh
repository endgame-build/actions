#!/usr/bin/env bash
# Create a changelog PR with the synthesized entry.
# Requires: SYNTHESIS_JSON, PR_NUMBER, PR_TITLE, PR_AUTHOR, GH_TOKEN env vars.
# Also requires: .actions/templates/CHANGELOG.md available for bootstrap.
set -eu

ENTRY=$(echo "$SYNTHESIS_JSON" | jq -r '.entry // empty')
[ -z "$ENTRY" ] && echo "No content — skipping." && exit 0

# Ensure CHANGELOG.md exists with [Unreleased] section
[ ! -f CHANGELOG.md ] && cp .actions/templates/CHANGELOG.md CHANGELOG.md
if ! grep -q '## \[Unreleased\]' CHANGELOG.md; then
  { head -1 CHANGELOG.md; echo -e "\n## [Unreleased]\n"; tail -n +2 CHANGELOG.md; } > /tmp/cl.md
  mv /tmp/cl.md CHANGELOG.md
fi

# Insert entry after [Unreleased]
awk -v entry="$ENTRY" '/^## \[Unreleased\]/ { print; print ""; print entry; next } { print }' \
  CHANGELOG.md > /tmp/cl.md
mv /tmp/cl.md CHANGELOG.md

# Create branch and PR
branch="changelog/pr-${PR_NUMBER}"
git push origin --delete "$branch" 2>/dev/null || true
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git checkout -b "$branch"
git add CHANGELOG.md
git commit -m "docs(changelog): update for PR #${PR_NUMBER} [skip ci]"
git push -u origin "$branch"
gh pr create --title "docs(changelog): update for #${PR_NUMBER}" \
  --body "Changelog update from PR #${PR_NUMBER}: ${PR_TITLE}" \
  --assignee "${PR_AUTHOR}" --label "changelog"
