"""Extract + validate the PR metadata JSON the agent emits as its final assistant message.

Pi (the agent) has no native ``--json-schema`` enforcement, so the final
assistant text may include narration around the JSON or wrap it in a markdown
fence. We extract the first balanced top-level ``{…}`` and validate the
parsed object against ``schema/pr-metadata.schema.json`` via ``jsonschema``.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path


class MetadataError(ValueError):
    """Raised when the agent's output can't be parsed into valid PR metadata."""


@dataclass(frozen=True)
class Metadata:
    """The PR metadata the agent emits. Schema: ``schema/pr-metadata.schema.json``."""

    title: str
    body: str
    addresses_comment_ids: tuple[str, ...]


_SCHEMA_PATH = Path(__file__).parent.parent.parent / "schema" / "pr-metadata.schema.json"


def extract_json_object(text: str) -> str:
    """Find the first balanced top-level JSON object in ``text``.

    Walks the string accounting for nested braces and escaped string
    contents. Returns the substring including the opening ``{`` and the
    matching ``}``. Raises :class:`MetadataError` if no balanced object is
    found.
    """
    in_str = False
    escape = False
    depth = 0
    start = -1
    for i, ch in enumerate(text):
        if in_str:
            if escape:
                escape = False
            elif ch == "\\":
                escape = True
            elif ch == '"':
                in_str = False
            continue
        if ch == '"':
            in_str = True
            continue
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start != -1:
                return text[start : i + 1]
    raise MetadataError("No balanced JSON object found in agent output")


def validate_metadata(raw: str) -> Metadata:
    """Extract + parse + schema-validate the PR metadata from an agent's final text.

    Raises :class:`MetadataError` if no JSON object can be extracted, the JSON
    is invalid, or the parsed object fails schema validation.
    """
    # `jsonschema` is only needed in the pr-open step; lazy import so other
    # subcommands don't take the dep.
    from jsonschema import FormatChecker, ValidationError, validate

    json_text = extract_json_object(raw)
    try:
        data = json.loads(json_text)
    except json.JSONDecodeError as e:
        raise MetadataError(f"Invalid JSON: {e}. Extracted: {json_text[:500]!r}") from e

    schema = json.loads(_SCHEMA_PATH.read_text(encoding="utf-8"))
    try:
        validate(data, schema, format_checker=FormatChecker())
    except ValidationError as e:
        path = "/".join(str(p) for p in e.absolute_path) or "<root>"
        raise MetadataError(f"Schema violation at {path}: {e.message}") from e

    return Metadata(
        title=data["title"],
        body=data["body"],
        addresses_comment_ids=tuple(data["addresses_comment_ids"]),
    )


# Comment-label prefix used to associate PRs with the comments they address.
# Kept short so `<prefix><uuid>` stays under GitHub's 50-char label cap
# (9 + 36 = 45).
COMMENT_LABEL_PREFIX = "tome-cid:"

# Common label applied to every tome-PR. Enables a single `label:` search to
# enumerate the backlog; removed by `consolidate` after a successful merge so
# the scan stays bounded over a repo's lifetime.
TOME_PR_LABEL = "auto:tome-comment-pr"


def comment_label(comment_id: str) -> str:
    return f"{COMMENT_LABEL_PREFIX}{comment_id}"


def labels_for_ids(ids: list[str] | tuple[str, ...]) -> list[str]:
    return [comment_label(cid) for cid in ids]


def comment_ids_from_labels(labels: list[dict]) -> list[str]:
    """Extract comment IDs from a list of label objects (as returned by ``gh pr view --json labels``)."""
    out: list[str] = []
    for lab in labels:
        name = lab.get("name", "")
        if name.startswith(COMMENT_LABEL_PREFIX):
            out.append(name.removeprefix(COMMENT_LABEL_PREFIX))
    return out
