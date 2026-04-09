#!/usr/bin/env bash
# Collect [Unreleased] sections from CHANGELOG.md across repos.
# Requires: REPOS, GH_TOKEN env vars.
# If GITHUB_OUTPUT is set, writes 'digest' and 'empty' step outputs.
# Otherwise prints digest to stdout.
set -eu

digest=""
for repo in $REPOS; do
  repo_short="${repo#endgame-build/}"

  raw=$(gh api "repos/${repo}/contents/CHANGELOG.md" --jq '.content' 2>/dev/null) || {
    digest="${digest}*${repo_short}*: _Could not retrieve changelog_\n"
    continue
  }
  content=$(echo "$raw" | base64 -d 2>/dev/null)

  unreleased=$(echo "$content" | sed -n '/^## \[Unreleased\]/,/^## \[/{ /^## \[Unreleased\]/d; /^## \[/d; p; }')

  if [ -z "$(echo "$unreleased" | tr -d '[:space:]')" ]; then
    continue
  fi

  digest="${digest}*${repo_short}*\n${unreleased}\n\n"
done

result=$(printf '%b' "$digest")

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  { echo "digest<<DIGEST_EOF"; echo "$result"; echo "DIGEST_EOF"; } >> "$GITHUB_OUTPUT"
  [ -z "$result" ] && echo "empty=true" >> "$GITHUB_OUTPUT" || echo "empty=false" >> "$GITHUB_OUTPUT"
else
  echo "$result"
fi
