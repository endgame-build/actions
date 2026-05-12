"""Shared helpers for process-tome-comments scripts.

Stdlib-only (Python 3.11+, available on Ubuntu GHA runners by default).
Subprocess wrappers around `git` and `gh`. JSON I/O. GitHub Actions
output and notice/error helpers.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any


# ── GitHub Actions output helpers ──────────────────────────────────────────


def gha_output(key: str, value: str) -> None:
    """Write a key=value line to $GITHUB_OUTPUT for the calling step."""
    path = os.environ.get("GITHUB_OUTPUT")
    if not path:
        # Fall back to stdout for local testing
        print(f"GHA_OUTPUT {key}={value}")
        return
    with open(path, "a", encoding="utf-8") as f:
        f.write(f"{key}={value}\n")


def notice(msg: str) -> None:
    print(f"::notice::{msg}")


def warning(msg: str) -> None:
    print(f"::warning::{msg}")


def error(msg: str) -> None:
    print(f"::error::{msg}", file=sys.stderr)


# ── subprocess wrappers ────────────────────────────────────────────────────


def run(
    cmd: list[str],
    *,
    check: bool = True,
    capture: bool = True,
    env: dict[str, str] | None = None,
    cwd: str | Path | None = None,
    stdin: str | None = None,
) -> subprocess.CompletedProcess[str]:
    """Run a subprocess with text I/O. Defaults to capture stdout/stderr."""
    return subprocess.run(
        cmd,
        check=check,
        text=True,
        capture_output=capture,
        env={**os.environ, **(env or {})},
        cwd=cwd,
        input=stdin,
    )


def gh_json(args: list[str], default: Any = None) -> Any:
    """Run `gh <args> --json ... ` and return parsed JSON. On error, return default."""
    try:
        r = run(["gh", *args])
        return json.loads(r.stdout)
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return default


def git(*args: str, check: bool = True, capture: bool = True) -> subprocess.CompletedProcess[str]:
    return run(["git", *args], check=check, capture=capture)


# ── data types ─────────────────────────────────────────────────────────────


@dataclass(frozen=True)
class Comment:
    id: str
    file_path: str
    block_index: int
    body: str
    author_login: str
    created_at: str
    is_resolved: bool

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
            is_resolved=bool(d.get("isResolved", False)),
        )


@dataclass
class Cluster:
    file_path: str
    block_index: int
    comments: list[Comment]  # sorted by created_at ascending

    @property
    def latest_id(self) -> str:
        return max(self.comments, key=lambda c: c.created_at).id

    @property
    def earliest_created_at(self) -> str:
        return min(self.comments, key=lambda c: c.created_at).created_at

    @property
    def authors(self) -> list[str]:
        return list(dict.fromkeys(c.author_login for c in self.comments))

    def to_dict(self) -> dict[str, Any]:
        return {
            "file_path": self.file_path,
            "block_index": self.block_index,
            "latest_id": self.latest_id,
            "earliest_created_at": self.earliest_created_at,
            "comments": [
                {
                    "id": c.id,
                    "filePath": c.file_path,
                    "blockIndex": c.block_index,
                    "body": c.body,
                    "authorLogin": c.author_login,
                    "createdAt": c.created_at,
                    "isResolved": c.is_resolved,
                }
                for c in self.comments
            ],
        }


# ── JSONL helpers ──────────────────────────────────────────────────────────


def load_comments(path: str | Path) -> list[Comment]:
    p = Path(path)
    if not p.exists():
        return []
    out: list[Comment] = []
    with p.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            out.append(Comment.from_jsonl_line(line))
    return out


# ── content sanitization ───────────────────────────────────────────────────


def sanitize_claude_mention(text: str) -> str:
    """Replace literal @claude with @-claude to avoid triggering other workflows
    that filter on `contains(comment.body, '@claude')`."""
    return text.replace("@claude", "@-claude")
