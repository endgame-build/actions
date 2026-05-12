#!/usr/bin/env python3
"""Compute the cluster list for this run.

Inputs (env):
    MAX_OPEN_PRS - Hard cap on open tome-comment PRs (positive int)
    GH_TOKEN     - Token for `gh pr list` queries
    RUNNER_TEMP  - GitHub Actions runner temp dir (or /tmp fallback)
    GITHUB_OUTPUT - GHA output file path

Side effects:
    Writes per-cluster prompt input files to ${RUNNER_TEMP}/clusters/<idx>.json
    for the per-cluster matrix step to consume.

Outputs (GITHUB_OUTPUT):
    matrix       - JSON array {include: [{idx, latest_id, ...}]}
    has_clusters - "true" if at least one cluster will be processed, else "false"

Behavior:
    1. Load .tome/comments.jsonl, keep only isResolved == False.
    2. Drop any comment with an existing PR (any state) carrying its label
       `tome-comment-id:<uuid>`. (Q2 idempotency.)
    3. Group by (filePath, blockIndex). One cluster per group.
    4. Sort clusters by oldest comment's createdAt ascending.
    5. Count open tome PRs; slots = MAX_OPEN_PRS - open_count.
       Take first `slots` clusters.
    6. Write each picked cluster to ${RUNNER_TEMP}/clusters/<idx>.json.
    7. Emit the matrix list to GITHUB_OUTPUT.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from _common import (
    Cluster,
    Comment,
    gh_json,
    gha_output,
    load_comments,
    notice,
)


def empty_output() -> None:
    gha_output("matrix", json.dumps({"include": []}))
    gha_output("has_clusters", "false")


def comment_has_existing_pr(comment_id: str) -> bool:
    result = gh_json(
        [
            "pr",
            "list",
            "--state",
            "all",
            "--search",
            f"label:tome-comment-id:{comment_id}",
            "--json",
            "number",
        ],
        default=[],
    )
    return bool(result)


def count_open_tome_prs() -> int:
    result = gh_json(
        [
            "pr",
            "list",
            "--state",
            "open",
            "--search",
            "label:tome-comment-id",
            "--json",
            "number",
        ],
        default=[],
    )
    return len(result)


def cluster_comments(comments: list[Comment]) -> list[Cluster]:
    by_key: dict[tuple[str, int], list[Comment]] = {}
    for c in comments:
        by_key.setdefault((c.file_path, c.block_index), []).append(c)
    clusters = [
        Cluster(
            file_path=fp,
            block_index=bi,
            comments=sorted(cs, key=lambda c: c.created_at),
        )
        for (fp, bi), cs in by_key.items()
    ]
    return sorted(clusters, key=lambda cl: cl.earliest_created_at)


def main() -> int:
    max_open_prs = int(os.environ.get("MAX_OPEN_PRS", "10"))
    runner_temp = Path(os.environ.get("RUNNER_TEMP", "/tmp"))
    clusters_dir = runner_temp / "clusters"
    clusters_dir.mkdir(parents=True, exist_ok=True)

    jsonl = Path(".tome/comments.jsonl")
    if not jsonl.exists():
        notice("No .tome/comments.jsonl in repo; nothing to do")
        empty_output()
        return 0

    # Step 1: unresolved
    unresolved = [c for c in load_comments(jsonl) if not c.is_resolved]
    print(f"Unresolved comments: {len(unresolved)}")
    if not unresolved:
        empty_output()
        return 0

    # Step 2: drop comments already covered by a PR
    fresh: list[Comment] = []
    for c in unresolved:
        if comment_has_existing_pr(c.id):
            print(f"skip {c.id}: existing PR")
            continue
        fresh.append(c)
    print(f"After idempotency filter: {len(fresh)}")
    if not fresh:
        empty_output()
        return 0

    # Step 3-4: cluster + sort
    clusters = cluster_comments(fresh)
    print(f"Clusters: {len(clusters)}")

    # Step 5: slot budget
    open_count = count_open_tome_prs()
    slots = max_open_prs - open_count
    print(f"Open tome-comment PRs: {open_count}; slots: {slots}")
    if slots <= 0:
        notice(f"Cap reached ({open_count}/{max_open_prs} open). Skipping process.")
        empty_output()
        return 0

    n_pick = min(slots, len(clusters))
    print(f"Will process {n_pick} clusters this run")

    # Step 6-7: write per-cluster JSON, build matrix
    matrix_include = []
    for i, cl in enumerate(clusters[:n_pick]):
        (clusters_dir / f"{i}.json").write_text(json.dumps(cl.to_dict()), encoding="utf-8")
        matrix_include.append(
            {
                "idx": str(i),
                "latest_id": cl.latest_id,
                "short_id": cl.latest_id[:8],
                "file_path": cl.file_path,
                "block_index": str(cl.block_index),
                "comment_ids_csv": ",".join(c.id for c in cl.comments),
            }
        )

    matrix = json.dumps({"include": matrix_include})
    gha_output("matrix", matrix)
    gha_output("has_clusters", "true")
    print(f"Matrix written: {matrix}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
