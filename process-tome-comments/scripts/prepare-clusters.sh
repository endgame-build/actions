#!/usr/bin/env bash
# Compute the cluster list for this run.
#
# Inputs (env):
#   MAX_OPEN_PRS         - Hard cap on open tome-comment PRs (positive int)
#   GH_TOKEN             - Token for `gh pr list` queries
#
# Side effects:
#   Writes per-cluster prompt input files to ${RUNNER_TEMP}/clusters/<idx>.json
#   for the per-cluster matrix step to consume.
#
# Outputs (GITHUB_OUTPUT):
#   matrix       - JSON array {include:[{idx, label_csv, latest_id, ...}]}
#   has_clusters - "true" if at least one cluster will be processed, else "false"
#
# Behavior:
#   1. Load .tome/comments.jsonl and filter to isResolved==false.
#   2. For each unresolved comment, drop if any PR (any state) carries label
#      tome-comment-id:<uuid>. (Q2 idempotency.)
#   3. Group remaining comments by (filePath, blockIndex). One cluster per group.
#   4. Sort clusters by oldest member's createdAt ascending.
#   5. Count currently-open PRs labeled tome-comment-id:*.
#      slots = MAX_OPEN_PRS - open_count. Take first `slots` clusters.
#   6. For each picked cluster, write a JSON file with everything the
#      per-cluster step needs (comments, file_path, block_index, authors).
#   7. Emit matrix list to GITHUB_OUTPUT.

set -euo pipefail

CLUSTERS_DIR="${RUNNER_TEMP:-/tmp}/clusters"
mkdir -p "$CLUSTERS_DIR"

if [[ ! -f .tome/comments.jsonl ]]; then
  echo "::notice::No .tome/comments.jsonl in repo; nothing to do"
  echo "matrix={\"include\":[]}" >> "$GITHUB_OUTPUT"
  echo "has_clusters=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

# Step 1: load unresolved comments
UNRESOLVED=$(jq -c -s 'map(select(.isResolved == false))' .tome/comments.jsonl)
N_UNRESOLVED=$(jq 'length' <<<"$UNRESOLVED")
echo "Unresolved comments: $N_UNRESOLVED"

if [[ "$N_UNRESOLVED" -eq 0 ]]; then
  echo "matrix={\"include\":[]}" >> "$GITHUB_OUTPUT"
  echo "has_clusters=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

# Step 2: drop comments with existing PRs (any state) carrying their label
COMMENTS_TO_PROCESS="[]"
while read -r comment; do
  uuid=$(jq -r '.id' <<<"$comment")
  existing=$(gh pr list --state all --search "label:tome-comment-id:${uuid}" --json number 2>/dev/null | jq 'length')
  if [[ "${existing:-0}" -gt 0 ]]; then
    echo "skip $uuid: ${existing} existing PR(s)"
    continue
  fi
  COMMENTS_TO_PROCESS=$(jq -c --argjson c "$comment" '. + [$c]' <<<"$COMMENTS_TO_PROCESS")
done < <(jq -c '.[]' <<<"$UNRESOLVED")

N_TO_PROCESS=$(jq 'length' <<<"$COMMENTS_TO_PROCESS")
echo "After idempotency filter: $N_TO_PROCESS"

if [[ "$N_TO_PROCESS" -eq 0 ]]; then
  echo "matrix={\"include\":[]}" >> "$GITHUB_OUTPUT"
  echo "has_clusters=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

# Step 3-4: cluster by (filePath, blockIndex), sort by oldest member's createdAt
CLUSTERS=$(jq -c '
  group_by(.filePath + " " + (.blockIndex | tostring))
  | map({
      file_path: .[0].filePath,
      block_index: .[0].blockIndex,
      comments: . | sort_by(.createdAt),
      earliest_created_at: (min_by(.createdAt).createdAt),
      latest_id: (max_by(.createdAt).id)
    })
  | sort_by(.earliest_created_at)
' <<<"$COMMENTS_TO_PROCESS")

N_CLUSTERS=$(jq 'length' <<<"$CLUSTERS")
echo "Clusters: $N_CLUSTERS"

# Step 5: count open PRs and decide slot budget
OPEN_COUNT=$(gh pr list --state open --search "label:tome-comment-id" --json number 2>/dev/null | jq 'length')
OPEN_COUNT="${OPEN_COUNT:-0}"
SLOTS=$(( MAX_OPEN_PRS - OPEN_COUNT ))
echo "Open tome-comment PRs: $OPEN_COUNT; slots: $SLOTS"

if [[ "$SLOTS" -le 0 ]]; then
  echo "::notice::Cap reached ($OPEN_COUNT/$MAX_OPEN_PRS open). Skipping process."
  echo "matrix={\"include\":[]}" >> "$GITHUB_OUTPUT"
  echo "has_clusters=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

# Step 6-7: take first $SLOTS clusters, write per-cluster JSON, build matrix
N_PICK=$(( SLOTS < N_CLUSTERS ? SLOTS : N_CLUSTERS ))
echo "Will process $N_PICK clusters this run"

MATRIX_INCLUDE="[]"
for ((i=0; i<N_PICK; i++)); do
  cluster=$(jq -c --argjson i "$i" '.[$i]' <<<"$CLUSTERS")

  # Write the full cluster JSON for the per-cluster step
  echo "$cluster" > "$CLUSTERS_DIR/$i.json"

  latest_id=$(jq -r '.latest_id' <<<"$cluster")
  file_path=$(jq -r '.file_path' <<<"$cluster")
  block_index=$(jq -r '.block_index' <<<"$cluster")
  comment_ids_csv=$(jq -r '[.comments[].id] | join(",")' <<<"$cluster")
  authors_csv=$(jq -r '[.comments[].authorLogin] | unique | join(",")' <<<"$cluster")
  short_id="${latest_id:0:8}"

  MATRIX_INCLUDE=$(jq -c --argjson item "$(jq -n \
    --arg idx "$i" \
    --arg latest_id "$latest_id" \
    --arg short_id "$short_id" \
    --arg file_path "$file_path" \
    --arg block_index "$block_index" \
    --arg comment_ids_csv "$comment_ids_csv" \
    --arg authors_csv "$authors_csv" \
    '{idx: $idx, latest_id: $latest_id, short_id: $short_id, file_path: $file_path, block_index: $block_index, comment_ids_csv: $comment_ids_csv, authors_csv: $authors_csv}')" \
    '. + [$item]' <<<"$MATRIX_INCLUDE")
done

MATRIX=$(jq -c --argjson inc "$MATRIX_INCLUDE" '{include: $inc}' <<<'{}')

{
  echo "matrix=$MATRIX"
  echo "has_clusters=true"
} >> "$GITHUB_OUTPUT"

echo "Matrix written: $MATRIX"
