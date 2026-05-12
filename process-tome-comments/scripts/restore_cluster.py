#!/usr/bin/env python3
"""Re-derive a cluster JSON file from the consumer's .tome/comments.jsonl.

Used by the `process` matrix step: each matrix item runs on a fresh runner
without access to the `prepare` job's runner-local files, so we reconstruct
the cluster from the matrix variables (which carry comment IDs by reference).

Inputs (env):
    IDS_CSV     - comma-separated comment IDs in this cluster
    FILE_PATH   - the cluster's source filePath
    BLOCK_INDEX - the cluster's blockIndex (string; parsed as int)
    LATEST_ID   - the latest comment id (for cluster.latest_id)
    IDX         - the matrix idx; output goes to ${RUNNER_TEMP}/clusters/<idx>.json
    RUNNER_TEMP - GHA runner temp dir
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def main() -> int:
    ids = [s for s in os.environ["IDS_CSV"].split(",") if s]
    file_path = os.environ["FILE_PATH"]
    block_index = int(os.environ["BLOCK_INDEX"])
    latest_id = os.environ["LATEST_ID"]
    idx = os.environ["IDX"]
    runner_temp = Path(os.environ.get("RUNNER_TEMP", "/tmp"))

    out_dir = runner_temp / "clusters"
    out_dir.mkdir(parents=True, exist_ok=True)

    target = set(ids)
    members = []
    for line in Path(".tome/comments.jsonl").read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        d = json.loads(line)
        if d["id"] in target and not d.get("isResolved", False):
            members.append(d)

    if not members:
        print(f"::error::Cluster {idx}: no matching unresolved comments found for "
              f"IDs {ids}. Has .tome/comments.jsonl drifted since `prepare`?",
              file=sys.stderr)
        return 1

    members.sort(key=lambda c: c["createdAt"])

    cluster = {
        "file_path": file_path,
        "block_index": block_index,
        "latest_id": latest_id,
        "earliest_created_at": members[0]["createdAt"],
        "comments": members,
    }

    (out_dir / f"{idx}.json").write_text(json.dumps(cluster), encoding="utf-8")
    print(f"Restored cluster {idx}: {len(members)} comment(s) at {file_path}#{block_index}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
