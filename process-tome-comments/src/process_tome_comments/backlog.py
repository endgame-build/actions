"""TomeBacklog: snapshot of the repo's currently-open tome-PRs.

The reject signal for a comment is `isResolved: true` in `.tome/comments.jsonl`
(set in Tome, or by the post-merge consolidate step). Closing a bot PR without
merging is the "this attempt wasn't good enough, try again" signal — it does
*not* mark the comment as addressed.

So backlog idempotency only needs the *open* set: don't open a second PR for
a comment that already has one in flight.
"""

from __future__ import annotations

import json
from dataclasses import dataclass

from .gha import run
from .metadata import TOME_PR_LABEL, comment_ids_from_labels


# Caps tome-PRs returned by the backlog scan. With the "open-only" rule the
# population is bounded by max_open_prs, so 1000 is wildly over-provisioned.
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
            "--state", "open",
            "--search", f'label:"{TOME_PR_LABEL}"',
            "--json", "number,labels",
            "--limit", str(FETCH_LIMIT),
        ])
        return cls.from_pr_records(json.loads(r.stdout))

    @classmethod
    def from_pr_records(cls, records: list[dict]) -> TomeBacklog:
        addressed: set[str] = set()
        for pr in records:
            addressed.update(comment_ids_from_labels(pr.get("labels", [])))
        return cls(frozenset(addressed), len(records))
