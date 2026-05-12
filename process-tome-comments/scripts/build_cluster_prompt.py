#!/usr/bin/env python3
"""Build the per-cluster agent prompt from the standing prelude + cluster context.

Inputs (env):
    CLUSTER_FILE - path to the cluster JSON (one of clusters/<idx>.json)
    PRELUDE_FILE - path to the standing prompt prelude (prompt/prelude.md)

Outputs:
    Writes the composed prompt to stdout. Caller redirects to a file passed
    to claude-code-base-action via prompt_file.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def main() -> int:
    cluster_file = Path(os.environ["CLUSTER_FILE"])
    prelude_file = Path(os.environ["PRELUDE_FILE"])

    cluster = json.loads(cluster_file.read_text(encoding="utf-8"))
    file_path = cluster["file_path"]
    block_index = cluster["block_index"]
    comments = cluster["comments"]
    comment_ids = ", ".join(c["id"] for c in comments)

    # Standing instructions, inlined verbatim
    sys.stdout.write(prelude_file.read_text(encoding="utf-8"))

    # Cluster-specific context
    sys.stdout.write(f"""

---

## Cluster context for THIS invocation

**Source file:** `{file_path}`
**Block index:** {block_index}
**Cluster size:** {len(comments)} comment(s)
**CLUSTER_COMMENT_IDS:** {comment_ids}

The comments to address (in arrival order):

""")

    for c in comments:
        sys.stdout.write(
            f"### Comment `{c['id']}` by @{c['authorLogin']} ({c['createdAt']})\n\n"
            f"{c['body']}\n\n"
        )

    sys.stdout.write("""
## What to do now

1. Read `.tome/comments.jsonl` to confirm the comment bodies match what's shown above (the workflow may stage stale data; the file is the source of truth).
2. Read the source file at the path above.
3. Apply the requested change(s) using the `Edit` or `Write` tool.
4. Emit the final JSON object as specified in ACTION B above. Bare JSON only — no markdown fence, no narration.

Remember: do NOT modify `.tome/comments.jsonl`, `.github/`, or any CI configuration. Do NOT include the literal string `@claude` in your output (paraphrase as `@-claude` if needed).
""")
    return 0


if __name__ == "__main__":
    sys.exit(main())
