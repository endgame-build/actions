#!/usr/bin/env bash
# Build the per-cluster agent prompt from the standing prelude + cluster context.
#
# Inputs (env):
#   CLUSTER_FILE  - path to the cluster JSON (one of clusters/<idx>.json)
#   PRELUDE_FILE  - path to the standing prompt prelude (prompt/prelude.md)
#
# Outputs:
#   Writes the composed prompt to stdout. Caller redirects to a file passed
#   to claude-code-base-action via prompt_file.

set -euo pipefail

CLUSTER_FILE="${CLUSTER_FILE:?CLUSTER_FILE not set}"
PRELUDE_FILE="${PRELUDE_FILE:?PRELUDE_FILE not set}"

cluster=$(cat "$CLUSTER_FILE")
file_path=$(jq -r '.file_path' <<<"$cluster")
block_index=$(jq -r '.block_index' <<<"$cluster")
comment_ids=$(jq -r '[.comments[].id] | join(", ")' <<<"$cluster")
n_comments=$(jq -r '.comments | length' <<<"$cluster")

# Inline the standing prelude verbatim. It contains the contract (ACTION A
# apply edits, ACTION B emit JSON) plus forbidden actions and the unactionable
# path. Concatenate cluster-specific context after.
cat "$PRELUDE_FILE"

cat <<EOF


---

## Cluster context for THIS invocation

**Source file:** \`$file_path\`
**Block index:** $block_index
**Cluster size:** $n_comments comment(s)
**CLUSTER_COMMENT_IDS:** $comment_ids

The comments to address (in arrival order):

EOF

jq -r '.comments[] |
  "### Comment `" + .id + "` by @" + .authorLogin + " (" + .createdAt + ")\n\n" +
  .body + "\n"
' <<<"$cluster"

cat <<'EOF'

## What to do now

1. Read `.tome/comments.jsonl` to confirm the comment bodies match what's shown above (the workflow may stage stale data; the file is the source of truth).
2. Read the source file at the path above.
3. Apply the requested change(s) using the `Edit` or `Write` tool.
4. Emit the final JSON object as specified in ACTION B above. Bare JSON only — no markdown fence, no narration.

Remember: do NOT modify `.tome/comments.jsonl`, `.github/`, or any CI configuration. Do NOT include the literal string `@claude` in your output (paraphrase as `@-claude` if needed).
EOF
