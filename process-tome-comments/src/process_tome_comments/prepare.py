"""``prepare`` subcommand: compute which clusters this run will process.

Reads ``.tome/comments.jsonl``, fetches the tome-PR backlog once, applies the
idempotency filter, clusters remaining comments, computes the slot budget,
takes the oldest ``slots`` clusters, writes each to
``$RUNNER_TEMP/clusters/<idx>.json``, and emits the matrix list to
``$GITHUB_OUTPUT``.

The per-cluster ``.json`` files are uploaded by the workflow as an artifact
and downloaded by each ``process`` matrix step. The matrix payload carries
only the lightweight ``{idx, short_id}`` for naming.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

from .backlog import TomeBacklog
from .comments import cluster_comments, load_comments
from .gha import gha_output, notice


def _emit_matrix(matrix_include: list[dict]) -> None:
    gha_output("matrix", json.dumps({"include": matrix_include}))
    gha_output("has_clusters", "true" if matrix_include else "false")


def main() -> int:
    max_open_prs = int(os.environ.get("MAX_OPEN_PRS", "10"))
    runner_temp = Path(os.environ.get("RUNNER_TEMP", "/tmp"))
    clusters_dir = runner_temp / "clusters"
    clusters_dir.mkdir(parents=True, exist_ok=True)

    jsonl = Path(".tome/comments.jsonl")
    if not jsonl.exists():
        notice("No .tome/comments.jsonl in repo; nothing to do")
        _emit_matrix([])
        return 0

    unresolved = [c for c in load_comments(jsonl) if not c.is_resolved]
    print(f"Unresolved comments: {len(unresolved)}")

    backlog = TomeBacklog.fetch()
    print(
        f"Backlog: {len(backlog.addressed_comment_ids)} addressed, "
        f"{backlog.open_pr_count} open"
    )

    fresh = [c for c in unresolved if not backlog.is_addressed(c.id)]
    print(f"After idempotency filter: {len(fresh)}")

    slots = max_open_prs - backlog.open_pr_count
    if slots <= 0:
        notice(
            f"Cap reached ({backlog.open_pr_count}/{max_open_prs} open). "
            "Skipping process."
        )
        _emit_matrix([])
        return 0

    clusters = cluster_comments(fresh)
    picked = clusters[:slots]
    print(f"Clusters: {len(clusters)}; will process {len(picked)}")

    matrix_include = []
    for i, cl in enumerate(picked):
        # Resolve block_index → (snippet, line range) from the current source
        # so the agent gets concrete anchor text instead of an opaque integer.
        # Silently passes through if the source file is missing or the block
        # index is out of range.
        source_path = Path(cl.file_path)
        if source_path.exists():
            cl = cl.with_block_location(source_path.read_text(encoding="utf-8"))
        cl.write_json_file(clusters_dir / f"{i}.json")
        matrix_include.append({"idx": str(i), "short_id": cl.latest_id[:8]})

    _emit_matrix(matrix_include)
    print(f"Matrix: {len(matrix_include)} cluster(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
