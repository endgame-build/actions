#!/usr/bin/env python3
"""Validate the agent's structured output, snapshot the diff, branch, push, open PR.

Inputs (env):
    AGENT_OUTPUT_PATH - path to a file containing the agent's last assistant
                        text. Expected to be (or contain) a JSON object
                        matching pr-metadata.schema.json.
    CLUSTER_FILE      - path to the cluster JSON
    APP_TOKEN         - tome-comments[bot] App token (for git push + gh)
    BOT_LOGIN         - "tome-comments[bot]" or whatever the App slug resolves to
    BOT_EMAIL         - <id>+<login>@users.noreply.github.com
    GITHUB_REPOSITORY - owner/repo (provided by GHA)

Exit codes:
    0 - PR opened OR empty diff (nothing to do, not a failure)
    1 - validation failed (Class A) - caller should log and continue
    2 - infrastructure error (push, gh) - matrix item fails; others proceed
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

from _common import error, git, notice, run, sanitize_claude_mention, warning


DISALLOWED_PATH_RE = re.compile(r"^(\.github/|\.tome/comments\.jsonl$|Taskfile\.yml$|scripts/)")


class Metadata(NamedTuple):
    title: str
    body: str
    addresses_comment_ids: list[str]


def fail(msg: str, *, code: int = 1) -> None:
    error(msg)
    sys.exit(code)


def extract_json_object(text: str) -> str:
    """Extract the first balanced top-level JSON object from `text`.

    Pi (unlike Claude Code's `--json-schema`) does not constrain the final
    assistant message, so the agent may emit narration around the JSON or
    wrap it in a code fence. This finds the first `{` and walks until the
    matching `}` accounting for nested braces and escaped string contents.
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
                return text[start:i + 1]
    raise ValueError("No balanced JSON object found in agent output")


def validate_metadata(raw: str) -> Metadata:
    try:
        json_text = extract_json_object(raw)
    except ValueError as e:
        fail(f"Agent output: {e}. First 500 chars: {raw[:500]!r}")
    try:
        data = json.loads(json_text)
    except json.JSONDecodeError as e:
        fail(f"Agent emitted invalid JSON: {e}. Extracted: {json_text[:500]!r}")
    if not isinstance(data, dict):
        fail("Agent output is not a JSON object")
    title = data.get("title")
    body = data.get("body")
    ids = data.get("addresses_comment_ids")
    if not isinstance(title, str) or not title:
        fail("Agent JSON missing or empty 'title'")
    if not isinstance(body, str) or not body:
        fail("Agent JSON missing or empty 'body'")
    if not isinstance(ids, list) or not ids:
        fail("Agent JSON missing or empty 'addresses_comment_ids'")
    for cid in ids:
        if not isinstance(cid, str):
            fail("addresses_comment_ids contains non-string item")
    return Metadata(title=title, body=body, addresses_comment_ids=ids)


def working_tree_has_changes() -> bool:
    git("add", "-A")
    r = git("diff", "--cached", "--quiet", check=False)
    return r.returncode != 0


def staged_disallowed_paths() -> list[str]:
    r = git("diff", "--cached", "--name-only")
    return [
        p for p in r.stdout.strip().splitlines() if DISALLOWED_PATH_RE.match(p)
    ]


def repo_default_branch(token: str, repo: str) -> str:
    r = run(["gh", "api", f"repos/{repo}", "--jq", ".default_branch"],
            env={"GH_TOKEN": token})
    return r.stdout.strip()


def main() -> int:
    agent_output_path = Path(os.environ["AGENT_OUTPUT_PATH"])
    cluster_file = Path(os.environ["CLUSTER_FILE"])
    app_token = os.environ["APP_TOKEN"]
    bot_login = os.environ["BOT_LOGIN"]
    bot_email = os.environ["BOT_EMAIL"]
    repo = os.environ["GITHUB_REPOSITORY"]

    cluster = json.loads(cluster_file.read_text(encoding="utf-8"))
    raw_output = agent_output_path.read_text(encoding="utf-8")

    # Validate + sanitize
    meta = validate_metadata(raw_output)
    title = sanitize_claude_mention(meta.title)
    if len(title) > 70:
        warning("Agent title >70 chars; truncating")
        title = title[:70]
    body = sanitize_claude_mention(meta.body)
    ids = meta.addresses_comment_ids

    # Working-tree check
    if not working_tree_has_changes():
        warning("Empty diff for cluster; agent decided no edit needed. "
                "Comment(s) remain unresolved.")
        return 0

    # Disallowed paths
    bad = staged_disallowed_paths()
    if bad:
        error("Agent modified disallowed paths; aborting cluster:")
        for p in bad:
            print(f"  {p}", file=sys.stderr)
        git("checkout", "--", ".")
        sys.exit(1)

    # Branch, commit, push
    latest_id = cluster["latest_id"]
    branch = f"tome-comment/{latest_id}"

    git("config", "user.name", bot_login)
    git("config", "user.email", bot_email)
    git("checkout", "-b", branch)
    git("commit", "-m", title, "-m", body)

    push_url = f"https://x-access-token:{app_token}@github.com/{repo}.git"
    try:
        run(["git", "push", push_url, f"HEAD:refs/heads/{branch}"])
    except subprocess.CalledProcessError as e:
        error(f"git push failed: {e.stderr}")
        sys.exit(2)

    # Open PR with labels and reviewers
    labels = ",".join(f"tome-comment-id:{cid}" for cid in ids)
    reviewers = ",".join(
        sorted({c["authorLogin"] for c in cluster["comments"]})
    )
    base = repo_default_branch(app_token, repo)

    try:
        run(
            [
                "gh", "pr", "create",
                "--base", base,
                "--head", branch,
                "--title", title,
                "--body", body,
                "--label", labels,
                "--reviewer", reviewers,
            ],
            env={"GH_TOKEN": app_token},
        )
    except subprocess.CalledProcessError as e:
        error(f"gh pr create failed: {e.stderr}")
        sys.exit(2)

    notice(f"Opened PR for cluster {latest_id} (labels: {labels}, reviewers: {reviewers})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
