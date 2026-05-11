#!/usr/bin/env bash
# After the agent has applied edits to the working tree, validate, snapshot,
# branch, commit, push, and open a PR.
#
# Inputs (env):
#   STRUCTURED_OUTPUT     - JSON string from claude-code-base-action's structured_output
#   CLUSTER_FILE          - path to the cluster JSON (for fallback metadata)
#   APP_TOKEN             - tome-comments[bot] App token (for git push + gh)
#   BOT_LOGIN             - "tome-comments[bot]" or whatever the App slug resolves to
#   BOT_EMAIL             - <id>+<login>@users.noreply.github.com
#   GITHUB_REPOSITORY     - owner/repo (provided by GHA)
#
# Behavior:
#   1. Validate STRUCTURED_OUTPUT is valid JSON conforming to schema:
#        {title:string, body:string, addresses_comment_ids:[uuid,...]}
#   2. Sanitize @claude → @-claude in title and body (Q5 content discipline).
#   3. Verify working tree has staged changes (else log empty-diff and exit 0).
#   4. Verify no disallowed paths touched.
#      Disallowed: .github/, .tome/comments.jsonl, Taskfile.yml, scripts/
#      (extend the list per repo conventions if needed).
#   5. Branch as tome-comment/<latest-uuid>, commit with title as subject,
#      push using App token.
#   6. gh pr create with title, body, labels (one tome-comment-id:<uuid> per
#      addressed comment), reviewers (cluster authors).
#
# Exit codes:
#   0 - PR opened OR empty-diff (nothing to do, not a failure)
#   1 - validation failed (Class A failure per Q10) - caller should log and continue
#   2 - infrastructure error (push, gh) - matrix item fails; other clusters proceed

set -euo pipefail

: "${STRUCTURED_OUTPUT:?STRUCTURED_OUTPUT not set}"
: "${CLUSTER_FILE:?CLUSTER_FILE not set}"
: "${APP_TOKEN:?APP_TOKEN not set}"
: "${BOT_LOGIN:?BOT_LOGIN not set}"
: "${BOT_EMAIL:?BOT_EMAIL not set}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY not set}"

cluster=$(cat "$CLUSTER_FILE")

# Step 1: validate JSON conforms to schema (loose — required fields + types)
if ! jq -e . <<<"$STRUCTURED_OUTPUT" >/dev/null 2>&1; then
  echo "::error::Agent emitted invalid JSON; skipping cluster"
  echo "$STRUCTURED_OUTPUT" | head -c 500 >&2
  exit 1
fi

title=$(jq -r '.title // empty' <<<"$STRUCTURED_OUTPUT")
body=$(jq -r '.body // empty' <<<"$STRUCTURED_OUTPUT")
ids_csv=$(jq -r '.addresses_comment_ids // [] | join(",")' <<<"$STRUCTURED_OUTPUT")

if [[ -z "$title" || -z "$body" || -z "$ids_csv" ]]; then
  echo "::error::Agent JSON missing required fields (title/body/addresses_comment_ids)"
  echo "$STRUCTURED_OUTPUT" | head -c 500 >&2
  exit 1
fi

if [[ "${#title}" -gt 70 ]]; then
  echo "::warning::Agent title >70 chars; truncating"
  title="${title:0:70}"
fi

# Step 2: sanitize @claude to prevent triggering other workflows
title="${title//@claude/@-claude}"
body="${body//@claude/@-claude}"

# Step 3: verify working-tree changes exist
git add -A
if git diff --cached --quiet; then
  echo "::warning::Empty diff for cluster; agent decided no edit needed. Comment(s) remain unresolved."
  exit 0
fi

# Step 4: reject disallowed paths
DISALLOWED='^\.github/|^\.tome/comments\.jsonl$|^Taskfile\.yml$|^scripts/'
if BAD=$(git diff --cached --name-only | grep -E "$DISALLOWED" || true); [[ -n "$BAD" ]]; then
  echo "::error::Agent modified disallowed paths; aborting cluster:"
  echo "$BAD" | sed 's/^/  /' >&2
  git checkout -- .
  exit 1
fi

# Step 5: branch, commit, push
latest_id=$(jq -r '.latest_id' <<<"$cluster")
branch="tome-comment/${latest_id}"

git config user.name "$BOT_LOGIN"
git config user.email "$BOT_EMAIL"

git checkout -b "$branch"
git commit -m "$title" -m "$body"
# Push using the App token. The push triggers pull_request:opened on the new
# branch only because the App token's identity is not GITHUB_TOKEN.
git push "https://x-access-token:${APP_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "HEAD:refs/heads/$branch"

# Step 6: open PR with labels and reviewers
labels_csv=""
IFS=',' read -ra ids <<<"$ids_csv"
for id in "${ids[@]}"; do
  labels_csv+="tome-comment-id:${id},"
done
labels_csv="${labels_csv%,}"

# Reviewers come from the cluster's unique authors
reviewers_csv=$(jq -r '[.comments[].authorLogin] | unique | join(",")' <<<"$cluster")

GH_TOKEN="$APP_TOKEN" gh pr create \
  --base "$(gh api "repos/${GITHUB_REPOSITORY}" --jq .default_branch)" \
  --head "$branch" \
  --title "$title" \
  --body "$body" \
  --label "$labels_csv" \
  --reviewer "$reviewers_csv"

echo "::notice::Opened PR for cluster $latest_id (labels: $labels_csv, reviewers: $reviewers_csv)"
