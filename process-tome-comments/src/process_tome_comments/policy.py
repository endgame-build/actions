"""Post-edit path policy: which staged paths the agent was forbidden to modify."""

from __future__ import annotations

import re

from .gha import git


DISALLOWED_PATHS = (
    r"^\.github/",
    r"^\.tome/comments\.jsonl$",
    r"^Taskfile\.yml$",
    r"^scripts/",
)

_DISALLOWED_PATH_RE = re.compile("(" + "|".join(DISALLOWED_PATHS) + ")")


def policy_violations() -> list[str]:
    r = git("diff", "--cached", "--name-only")
    return [p for p in r.stdout.strip().splitlines() if _DISALLOWED_PATH_RE.match(p)]
