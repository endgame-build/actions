"""Post-edit path policy: which staged paths the agent was forbidden to modify."""

from __future__ import annotations

import re

from .gha import git


DISALLOWED_PATHS = (
    # The reusable workflow's own trigger configuration. Letting the agent
    # rewrite this would break the next run.
    r"^\.github/",
    # The post-merge `consolidate` step owns resolution writes. If the agent
    # also writes here, consolidate either fails or loses comment state.
    r"^\.tome/comments\.jsonl$",
)

_DISALLOWED_PATH_RE = re.compile("(" + "|".join(DISALLOWED_PATHS) + ")")


def policy_violations() -> list[str]:
    r = git("diff", "--cached", "--name-only")
    return [p for p in r.stdout.strip().splitlines() if _DISALLOWED_PATH_RE.match(p)]
