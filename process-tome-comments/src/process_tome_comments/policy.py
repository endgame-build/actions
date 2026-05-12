"""Path policy: which working-tree paths the agent is forbidden to modify.

Enforced by inspecting the staged diff after the agent runs. If any matching
path appears, the cluster is aborted and the working tree restored.

See ``CONTEXT.md`` for the conceptual definition of "disallowed paths."
"""

from __future__ import annotations

import re


# Paths the agent must not modify. The agent is told this in the prelude,
# and snapshot_and_pr enforces it after the fact.
DISALLOWED_PATHS = (
    r"^\.github/",
    r"^\.tome/comments\.jsonl$",
    r"^Taskfile\.yml$",
    r"^scripts/",
)

DISALLOWED_PATH_RE = re.compile("(" + "|".join(DISALLOWED_PATHS) + ")")


def is_disallowed(path: str) -> bool:
    return bool(DISALLOWED_PATH_RE.match(path))


def filter_disallowed(paths: list[str]) -> list[str]:
    return [p for p in paths if is_disallowed(p)]
