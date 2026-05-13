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
from .comments import Comment, Cluster, cluster_comments, load_comments
from .gha import gha_output, notice


def _empty_output() -> None:
    gha_output("matrix", json.dumps({"include": []}))
    gha_output("has_clusters", "false")


def filter_unhandled(comments: list[Comment], backlog: TomeBacklog) -> list[Comment]:
    out: list[Comment] = []
    for c in comments:
        if backlog.is_addressed(c.id):
            print(f"skip {c.id}: existing PR")
            continue
        out.append(c)
    return out


def pick_clusters(
    clusters: list[Cluster],
    *,
    max_open_prs: int,
    open_count: int,
) -> list[Cluster]:
    slots = max_open_prs - open_count
    if slots <= 0:
        notice(f"Cap reached ({open_count}/{max_open_prs} open). Skipping process.")
        return []
    return clusters[:slots]


def main() -> int:
    max_open_prs = int(os.environ.get("MAX_OPEN_PRS", "10"))
    runner_temp = Path(os.environ.get("RUNNER_TEMP", "/tmp"))
    clusters_dir = runner_temp / "clusters"
    clusters_dir.mkdir(parents=True, exist_ok=True)

    jsonl = Path(".tome/comments.jsonl")
    if not jsonl.exists():
        notice("No .tome/comments.jsonl in repo; nothing to do")
        _empty_output()
        return 0

    unresolved = [c for c in load_comments(jsonl) if not c.is_resolved]
    print(f"Unresolved comments: {len(unresolved)}")
    if not unresolved:
        _empty_output()
        return 0

    backlog = TomeBacklog.fetch()
    print(
        f"Backlog: {len(backlog.addressed_comment_ids)} addressed, "
        f"{backlog.open_pr_count} open"
    )

    fresh = filter_unhandled(unresolved, backlog)
    print(f"After idempotency filter: {len(fresh)}")
    if not fresh:
        _empty_output()
        return 0

    clusters = cluster_comments(fresh)
    print(f"Clusters: {len(clusters)}")

    picked = pick_clusters(
        clusters, max_open_prs=max_open_prs, open_count=backlog.open_pr_count
    )
    print(f"Will process {len(picked)} clusters")
    if not picked:
        _empty_output()
        return 0

    matrix_include = []
    for i, cl in enumerate(picked):
        # Resolve block_index → (snippet, line range) from the current source so
        # the agent gets concrete anchor text, not just an opaque integer.
        # Silently passes through if the source file is missing or block_index
        # is out of range.
        source_path = Path(cl.file_path)
        if source_path.exists():
            cl = cl.with_block_location(source_path.read_text(encoding="utf-8"))
        cl.write_json_file(clusters_dir / f"{i}.json")
        matrix_include.append({"idx": str(i), "short_id": cl.latest_id[:8]})

    matrix = json.dumps({"include": matrix_include})
    gha_output("matrix", matrix)
    gha_output("has_clusters", "true")
    print(f"Matrix written: {matrix}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
