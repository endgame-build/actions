#!/usr/bin/env bash
# Collect [Unreleased] sections from CHANGELOG.md across repos.
# Requires: REPOS (space-separated), GH_TOKEN env vars.
# Output: prints Slack-formatted digest to stdout. Empty if no changes.
set -eu

digest=""
for repo in $REPOS; do
  repo_short="${repo#endgame-build/}"

  content=$(gh api "repos/${repo}/contents/CHANGELOG.md" \
    --jq '.content' 2>/dev/null | base64 -d 2>/dev/null) || {
    digest="${digest}*${repo_short}*: _Could not retrieve changelog_\n"
    continue
  }

  unreleased=$(echo "$content" | sed -n '/^## \[Unreleased\]/,/^## \[/{ /^## \[Unreleased\]/d; /^## \[/d; p; }')

  if [ -z "$(echo "$unreleased" | tr -d '[:space:]')" ]; then
    continue
  fi

  digest="${digest}*${repo_short}*\n${unreleased}\n\n"
done

printf '%b' "$digest"
