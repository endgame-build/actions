#!/usr/bin/env bash
# Build the per-cluster agent prompt from skill content + cluster context.
#
# Inputs (env):
#   CLUSTER_FILE  - path to the cluster JSON (one of clusters/<idx>.json)
#   SKILL_FILE    - path to the SKILL.md to inline
#
# Outputs:
#   Writes the composed prompt to stdout. Caller redirects to a file
#   passed to claude-code-action via prompt_file or prompt input.

set -euo pipefail

CLUSTER_FILE="${CLUSTER_FILE:?CLUSTER_FILE not set}"
SKILL_FILE="${SKILL_FILE:?SKILL_FILE not set}"

cluster=$(cat "$CLUSTER_FILE")
file_path=$(jq -r '.file_path' <<<"$cluster")
block_index=$(jq -r '.block_index' <<<"$cluster")
comment_ids=$(jq -r '[.comments[].id] | join(", ")' <<<"$cluster")
n_comments=$(jq -r '.comments | length' <<<"$cluster")

# Compose the prompt: skill content first (background + contract), then concrete
# cluster context. Strip the YAML frontmatter from the skill — it's metadata
# for skill registration, not agent context, and a leading `---` confuses
# CLI prompt parsers.
awk '
  BEGIN { in_fm = 0; done = 0 }
  /^---$/ {
    if (!done && NR == 1) { in_fm = 1; next }
    if (in_fm) { in_fm = 0; done = 1; next }
  }
  !in_fm { print }
' "$SKILL_FILE"

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

1. Read \`.tome/comments.jsonl\` to confirm the comment bodies match what's shown above (the workflow may stage stale data; the file is the source of truth).
2. Read the source file at the path above.
3. Apply the requested change(s) using the `Edit` or `Write` tool.
4. Emit the final JSON object as specified in ACTION B above. Bare JSON only — no markdown fence, no narration.

Remember: do NOT modify `.tome/comments.jsonl`, `.github/`, or any CI configuration. Do NOT include the literal string `@claude` in your output (paraphrase as `@-claude` if needed).
EOF
