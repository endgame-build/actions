#!/usr/bin/env bash
# Listener: on pull_request:closed, if the PR was merged AND has tome-comment-id
# labels, mark each addressed comment as resolved in .tome/comments.jsonl on
# the default branch via a single bot commit.
#
# Inputs (env):
#   PR_NUMBER          - the closed PR number (from github.event.pull_request.number)
#   PR_MERGED          - "true" if merged, "false" if just closed
#   APP_TOKEN          - tome-comments[bot] App token
#   BOT_LOGIN          - bot login
#   BOT_EMAIL          - bot commit email
#   GITHUB_REPOSITORY  - owner/repo
#
# Behavior:
#   1. If PR was not merged, exit 0 (Q2: closed-not-merged is a safety-net
#      signal; the comment stays unresolved unless user resolves in Tome).
#   2. Read all tome-comment-id:<uuid> labels on the PR.
#   3. If no such labels, exit 0 (not a tome PR).
#   4. Update .tome/comments.jsonl: for each id, set isResolved=true,
#      resolvedBy=BOT_LOGIN, resolvedAt=<ISO now>.
#   5. Commit and push to default branch.
#   6. (Multi-approach sibling close — deferred. Single PR per cluster at v1.)

set -euo pipefail

: "${PR_NUMBER:?PR_NUMBER not set}"
: "${PR_MERGED:?PR_MERGED not set}"
: "${APP_TOKEN:?APP_TOKEN not set}"
: "${BOT_LOGIN:?BOT_LOGIN not set}"
: "${BOT_EMAIL:?BOT_EMAIL not set}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY not set}"

if [[ "$PR_MERGED" != "true" ]]; then
  echo "PR #${PR_NUMBER} closed without merge; safety-net filter handles re-run loop, no JSONL update."
  exit 0
fi

# Get the labels on the merged PR
LABELS_JSON=$(GH_TOKEN="$APP_TOKEN" gh pr view "$PR_NUMBER" --json labels)
COMMENT_IDS=$(jq -r '.labels[].name | select(startswith("tome-comment-id:")) | sub("^tome-comment-id:"; "")' <<<"$LABELS_JSON")

if [[ -z "$COMMENT_IDS" ]]; then
  echo "PR #${PR_NUMBER} has no tome-comment-id labels; not a tome PR."
  exit 0
fi

echo "Resolving comment(s) on merge of PR #${PR_NUMBER}:"
echo "$COMMENT_IDS" | sed 's/^/  /'

if [[ ! -f .tome/comments.jsonl ]]; then
  echo "::warning::PR #${PR_NUMBER} merged but .tome/comments.jsonl no longer exists; nothing to update."
  exit 0
fi

NOW=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")

# Read JSONL, transform matching comments to isResolved=true, write back atomically
TMP=$(mktemp)
while IFS= read -r line; do
  cid=$(jq -r '.id' <<<"$line")
  if echo "$COMMENT_IDS" | grep -qFx "$cid"; then
    jq -c \
      --arg by "$BOT_LOGIN" \
      --arg at "$NOW" \
      '. + {isResolved: true, resolvedBy: $by, resolvedAt: $at, updatedAt: $at}' \
      <<<"$line" >> "$TMP"
  else
    echo "$line" >> "$TMP"
  fi
done < .tome/comments.jsonl

mv "$TMP" .tome/comments.jsonl

# Commit + push (default branch)
git config user.name "$BOT_LOGIN"
git config user.email "$BOT_EMAIL"

DEFAULT_BRANCH=$(GH_TOKEN="$APP_TOKEN" gh api "repos/${GITHUB_REPOSITORY}" --jq .default_branch)

# Short SHA(s) for the commit message
SHORT_IDS=$(echo "$COMMENT_IDS" | awk '{print substr($1,1,8)}' | paste -sd "," -)
N_COMMENTS=$(echo "$COMMENT_IDS" | wc -l)

git add .tome/comments.jsonl
if git diff --cached --quiet; then
  echo "::warning::No JSONL changes after transform — comments may already be resolved."
  exit 0
fi

if [[ "$N_COMMENTS" -eq 1 ]]; then
  MSG="chore(tome): resolve comment $SHORT_IDS"
else
  MSG="chore(tome): resolve $N_COMMENTS comments ($SHORT_IDS)"
fi

git commit -m "$MSG" -m "Resolved by merge of #${PR_NUMBER}."
git push "https://x-access-token:${APP_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "HEAD:${DEFAULT_BRANCH}"

echo "::notice::Resolved $N_COMMENTS comment(s) on $DEFAULT_BRANCH"
