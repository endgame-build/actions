"""``pr-open`` subcommand: snapshot the agent's diff, branch, push, open PR.

Inputs come from env vars set by the workflow:

- ``AGENT_OUTPUT_PATH``  — file containing the agent's final assistant text
- ``MATRIX_IDX``         — index of the cluster under ``$RUNNER_TEMP/clusters/<idx>.json``
- ``APP_TOKEN``          — App-minted token; not in the agent step's env
- ``APP_SLUG``           — App slug from ``actions/create-github-app-token``
- ``GITHUB_REPOSITORY``  — owner/repo (GHA-provided)
"""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

from .bot_git import (
    BotIdentity,
    commit,
    configure_git_identity,
    default_branch,
    gh,
    push,
)
from .comments import Cluster, sanitize_claude_mention
from .gha import error, git, notice, warning
from .metadata import MetadataError, labels_for_ids, validate_metadata
from .policy import filter_disallowed


def working_tree_has_changes() -> bool:
    git("add", "-A")
    r = git("diff", "--cached", "--quiet", check=False)
    return r.returncode != 0


def staged_disallowed_paths() -> list[str]:
    r = git("diff", "--cached", "--name-only")
    return filter_disallowed(r.stdout.strip().splitlines())


def main() -> int:
    runner_temp = Path(os.environ.get("RUNNER_TEMP", "/tmp"))
    matrix_idx = os.environ["MATRIX_IDX"]
    agent_output_path = Path(os.environ["AGENT_OUTPUT_PATH"])
    cluster_file = runner_temp / "clusters" / f"{matrix_idx}.json"
    app_token = os.environ["APP_TOKEN"]
    app_slug = os.environ["APP_SLUG"]
    repo = os.environ["GITHUB_REPOSITORY"]

    cluster = Cluster.from_json_file(cluster_file)
    raw_output = agent_output_path.read_text(encoding="utf-8")

    try:
        meta = validate_metadata(raw_output)
    except MetadataError as e:
        error(f"Agent output rejected: {e}")
        return 1

    title = sanitize_claude_mention(meta.title)
    if len(title) > 70:
        warning("Agent title >70 chars; truncating")
        title = title[:70]
    body = sanitize_claude_mention(meta.body)
    ids = list(meta.addresses_comment_ids)

    if not working_tree_has_changes():
        warning(
            "Empty diff for cluster; agent decided no edit needed. "
            "Comment(s) remain unresolved."
        )
        return 0

    bad = staged_disallowed_paths()
    if bad:
        error("Agent modified disallowed paths; aborting cluster:")
        for p in bad:
            print(f"  {p}", file=sys.stderr)
        git("checkout", "--", ".")
        return 1

    identity = BotIdentity.resolve(token=app_token, app_slug=app_slug)
    configure_git_identity(identity)

    branch = f"tome-comment/{cluster.latest_id}"
    git("checkout", "-b", branch)
    commit(subject=title, body=body)

    try:
        push(identity, repo=repo, refspec=f"HEAD:refs/heads/{branch}")
    except subprocess.CalledProcessError:
        return 2

    labels = ",".join(labels_for_ids(ids))
    reviewers = ",".join(sorted(cluster.authors))
    base = default_branch(identity, repo)

    try:
        gh(
            [
                "pr", "create",
                "--base", base,
                "--head", branch,
                "--title", title,
                "--body", body,
                "--label", labels,
                "--reviewer", reviewers,
            ],
            identity,
        )
    except subprocess.CalledProcessError as e:
        error(f"gh pr create failed: {e.stderr}")
        return 2

    notice(
        f"Opened PR for cluster {cluster.latest_id} "
        f"(labels: {labels}, reviewers: {reviewers})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
