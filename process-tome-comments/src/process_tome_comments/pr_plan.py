"""PRPlan: pure transform from (Cluster, agent_text) to a ready-to-submit PR shape."""

from __future__ import annotations

from dataclasses import dataclass

from .comments import Cluster
from .metadata import TOME_PR_LABEL, labels_for_ids, validate_metadata


TITLE_MAX_LEN = 70


@dataclass(frozen=True)
class PRPlan:
    title: str
    body: str
    branch: str
    labels: tuple[str, ...]
    reviewers: tuple[str, ...]

    @classmethod
    def build(cls, cluster: Cluster, agent_text: str) -> PRPlan:
        meta = validate_metadata(agent_text)
        title = _sanitize_claude_mention(meta.title)[:TITLE_MAX_LEN]
        body = _sanitize_claude_mention(meta.body)
        return cls(
            title=title,
            body=body,
            branch=f"tome-comment/{cluster.latest_id}",
            labels=(TOME_PR_LABEL, *labels_for_ids(meta.addresses_comment_ids)),
            reviewers=tuple(sorted(cluster.authors)),
        )


def _sanitize_claude_mention(text: str) -> str:
    # Other org workflows filter on `contains(comment.body, '@claude')`;
    # a literal mention here would re-trigger them.
    return text.replace("@claude", "@-claude")
