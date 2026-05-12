"""TomeBacklog: snapshot of the repo's tome-PR state used by ``prepare``."""

from __future__ import annotations

import json
from dataclasses import dataclass

from .gha import run
from .metadata import TOME_PR_LABEL, comment_ids_from_labels


# Caps total tome-PRs returned by the backlog scan. Sized for any realistic
# repo lifetime under the drop-label-after-merge regime, where the population
# is bounded by closed-without-merge volume (reviewer-driven, low).
FETCH_LIMIT = 1000


@dataclass(frozen=True)
class TomeBacklog:
    addressed_comment_ids: frozenset[str]
    open_pr_count: int

    def is_addressed(self, comment_id: str) -> bool:
        return comment_id in self.addressed_comment_ids

    @classmethod
    def fetch(cls) -> TomeBacklog:
        r = run([
            "gh", "pr", "list",
            "--state", "all",
            "--search", f'label:"{TOME_PR_LABEL}"',
            "--json", "number,state,labels",
            "--limit", str(FETCH_LIMIT),
        ])
        return cls.from_pr_records(json.loads(r.stdout))

    @classmethod
    def from_pr_records(cls, records: list[dict]) -> TomeBacklog:
        addressed: set[str] = set()
        open_count = 0
        for pr in records:
            addressed.update(comment_ids_from_labels(pr.get("labels", [])))
            if pr.get("state") == "OPEN":
                open_count += 1
        return cls(frozenset(addressed), open_count)
