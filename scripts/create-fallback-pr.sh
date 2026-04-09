#!/usr/bin/env bash
# Create a fallback changelog PR using raw git-cliff output.
# Requires: PR_NUMBER, PR_TITLE, PR_AUTHOR, GH_TOKEN env vars.
set -eu

git diff --quiet CHANGELOG.md 2>/dev/null && echo "No changes" && exit 0

branch="changelog/pr-${PR_NUMBER}"
git push origin --delete "$branch" 2>/dev/null || true
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git checkout -b "$branch"
git add CHANGELOG.md
git commit -m "docs(changelog): update for PR #${PR_NUMBER} [skip ci]"
git push -u origin "$branch"
gh pr create --title "docs(changelog): update for #${PR_NUMBER}" \
  --body "Changelog from PR #${PR_NUMBER}: ${PR_TITLE}. AI unavailable — raw git-cliff." \
  --assignee "${PR_AUTHOR}" --label "changelog"
