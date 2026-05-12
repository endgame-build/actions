#!/usr/bin/env python3
"""Re-derive a cluster JSON file from the consumer's .tome/comments.jsonl.

Used by the `process` matrix step: each matrix item runs on a fresh runner
without access to the `prepare` job's runner-local files, so we reconstruct
the cluster from the matrix variables (which carry comment IDs by reference).

Inputs (env):
    IDS_CSV     - comma-separated comment IDs in this cluster
    FILE_PATH   - the cluster's source filePath
    BLOCK_INDEX - the cluster's blockIndex (string; parsed as int)
    IDX         - the matrix idx; output goes to ${RUNNER_TEMP}/clusters/<idx>.json
    RUNNER_TEMP - GHA runner temp dir
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from _common import Cluster, error, load_comments


def main() -> int:
    target = set(s for s in os.environ["IDS_CSV"].split(",") if s)
    file_path = os.environ["FILE_PATH"]
    block_index = int(os.environ["BLOCK_INDEX"])
    idx = os.environ["IDX"]
    runner_temp = Path(os.environ.get("RUNNER_TEMP", "/tmp"))

    out_dir = runner_temp / "clusters"
    out_dir.mkdir(parents=True, exist_ok=True)

    members = [
        c for c in load_comments(".tome/comments.jsonl")
        if c.id in target and not c.is_resolved
    ]
    if not members:
        error(f"Cluster {idx}: no matching unresolved comments found for "
              f"IDs {sorted(target)}. Has .tome/comments.jsonl drifted since `prepare`?")
        return 1

    cluster = Cluster(
        file_path=file_path,
        block_index=block_index,
        comments=sorted(members, key=lambda c: c.created_at),
    )

    (out_dir / f"{idx}.json").write_text(json.dumps(cluster.to_dict()), encoding="utf-8")
    print(f"Restored cluster {idx}: {len(members)} comment(s) at {file_path}#{block_index}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
