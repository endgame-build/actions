"""Comment + Cluster domain types and JSONL I/O.

The single source of truth for the ``.tome/comments.jsonl`` schema.
All scripts go through these types — no ad-hoc ``json.loads`` + dict
indexing elsewhere in the package.

See `CONTEXT.md` for the conceptual definition of Comment and Cluster.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


@dataclass(frozen=True)
class Comment:
    """One entry in ``.tome/comments.jsonl``.

    Field names mirror the Tome editor's JSON schema (camelCase wire format,
    snake_case Python attribute names). Round-trips through
    :meth:`from_jsonl_line` and :meth:`to_dict` exactly preserve the schema.
    """

    id: str
    file_path: str
    block_index: int
    body: str
    author_login: str
    created_at: str
    updated_at: str
    is_resolved: bool
    resolved_by: str | None = None
    resolved_at: str | None = None
    author_avatar_url: str | None = None
    block_snippet: str = ""
    replies: tuple[Any, ...] = ()

    @classmethod
    def from_jsonl_line(cls, line: str) -> Comment:
        d = json.loads(line)
        return cls(
            id=d["id"],
            file_path=d["filePath"],
            block_index=d["blockIndex"],
            body=d["body"],
            author_login=d["authorLogin"],
            created_at=d["createdAt"],
            updated_at=d.get("updatedAt", d["createdAt"]),
            is_resolved=bool(d.get("isResolved", False)),
            resolved_by=d.get("resolvedBy"),
            resolved_at=d.get("resolvedAt"),
            author_avatar_url=d.get("authorAvatarUrl"),
            block_snippet=d.get("blockSnippet", ""),
            replies=tuple(d.get("replies", [])),
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "filePath": self.file_path,
            "blockIndex": self.block_index,
            "blockSnippet": self.block_snippet,
            "body": self.body,
            "authorLogin": self.author_login,
            "authorAvatarUrl": self.author_avatar_url,
            "replies": list(self.replies),
            "isResolved": self.is_resolved,
            "resolvedBy": self.resolved_by,
            "resolvedAt": self.resolved_at,
            "createdAt": self.created_at,
            "updatedAt": self.updated_at,
        }

    def resolved(self, *, by: str, at: str) -> Comment:
        """Return a copy with ``isResolved`` set and ``resolved*`` populated."""
        return Comment(
            id=self.id,
            file_path=self.file_path,
            block_index=self.block_index,
            body=self.body,
            author_login=self.author_login,
            created_at=self.created_at,
            updated_at=at,
            is_resolved=True,
            resolved_by=by,
            resolved_at=at,
            author_avatar_url=self.author_avatar_url,
            block_snippet=self.block_snippet,
            replies=self.replies,
        )


@dataclass(frozen=True)
class Cluster:
    """A group of comments sharing the same ``(file_path, block_index)``.

    The unit of agent invocation. ``comments`` is sorted ascending by
    ``created_at``.
    """

    file_path: str
    block_index: int
    comments: tuple[Comment, ...]

    @property
    def latest_id(self) -> str:
        return max(self.comments, key=lambda c: c.created_at).id

    @property
    def earliest_created_at(self) -> str:
        return min(self.comments, key=lambda c: c.created_at).created_at

    @property
    def authors(self) -> list[str]:
        """Unique author logins, preserving first-seen order."""
        return list(dict.fromkeys(c.author_login for c in self.comments))

    @property
    def comment_ids(self) -> list[str]:
        return [c.id for c in self.comments]

    def to_dict(self) -> dict[str, Any]:
        return {
            "file_path": self.file_path,
            "block_index": self.block_index,
            "latest_id": self.latest_id,
            "earliest_created_at": self.earliest_created_at,
            "comments": [c.to_dict() for c in self.comments],
        }

    @classmethod
    def from_dict(cls, d: dict[str, Any]) -> Cluster:
        comments = [
            Comment.from_jsonl_line(json.dumps(c)) if isinstance(c, dict) else c
            for c in d["comments"]
        ]
        return cls(
            file_path=d["file_path"],
            block_index=int(d["block_index"]),
            comments=tuple(sorted(comments, key=lambda c: c.created_at)),
        )

    @classmethod
    def from_json_file(cls, path: str | Path) -> Cluster:
        return cls.from_dict(json.loads(Path(path).read_text(encoding="utf-8")))

    def write_json_file(self, path: str | Path) -> None:
        Path(path).write_text(json.dumps(self.to_dict()), encoding="utf-8")


def load_comments(path: str | Path) -> list[Comment]:
    """Load all comments from a JSONL file. Returns ``[]`` if the file is missing."""
    p = Path(path)
    if not p.exists():
        return []
    out: list[Comment] = []
    for line in p.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        out.append(Comment.from_jsonl_line(line))
    return out


def write_comments(path: str | Path, comments: Iterable[Comment]) -> None:
    """Write comments back to a JSONL file. Compact form, one object per line."""
    lines = [
        json.dumps(c.to_dict(), ensure_ascii=False, separators=(",", ":"))
        for c in comments
    ]
    Path(path).write_text("\n".join(lines) + "\n", encoding="utf-8")


def cluster_comments(comments: Iterable[Comment]) -> list[Cluster]:
    """Group comments by ``(file_path, block_index)``; sort clusters by earliest member."""
    by_key: dict[tuple[str, int], list[Comment]] = {}
    for c in comments:
        by_key.setdefault((c.file_path, c.block_index), []).append(c)
    clusters = [
        Cluster(
            file_path=fp,
            block_index=bi,
            comments=tuple(sorted(cs, key=lambda c: c.created_at)),
        )
        for (fp, bi), cs in by_key.items()
    ]
    return sorted(clusters, key=lambda cl: cl.earliest_created_at)


def sanitize_claude_mention(text: str) -> str:
    """Replace literal ``@claude`` with ``@-claude``.

    Avoids triggering other org workflows that filter on
    ``contains(comment.body, '@claude')``.
    """
    return text.replace("@claude", "@-claude")
