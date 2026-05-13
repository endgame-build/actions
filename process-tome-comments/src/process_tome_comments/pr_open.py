"""``pr-open`` subcommand: validate agent output, snapshot diff, branch, push, open PR."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

from .bot import BotSession
from .comments import Cluster
from .gha import error, git, notice, warning
from .metadata import COMMENT_LABEL_PREFIX, TOME_PR_LABEL, MetadataError
from .policy import policy_violations
from .pr_plan import PRPlan


def working_tree_has_changes() -> bool:
    git("add", "-A")
    r = git("diff", "--cached", "--quiet", check=False)
    return r.returncode != 0


def _ensure_labels(session: BotSession, labels: tuple[str, ...]) -> None:
    # `gh pr create --label X` fails if X doesn't exist on the repo. Per-id
    # `tome-cid:<uuid>` labels are unique per comment, so they can't be
    # pre-seeded — create them lazily here. `--force` is idempotent: creates
    # if missing, updates color/description otherwise.
    for label in labels:
        if label == TOME_PR_LABEL:
            color, desc = "fbca04", "Automated PR opened by process-tome-comments"
        elif label.startswith(COMMENT_LABEL_PREFIX):
            color, desc = "0e8a16", "Addresses a Tome comment id"
        else:
            color, desc = "ededed", ""
        try:
            session.gh(
                ["label", "create", label, "--force", "--color", color,
                 "--description", desc]
            )
        except subprocess.CalledProcessError as e:
            warning(f"could not ensure label {label!r}: {e.stderr.strip()[:200]}")


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
        plan = PRPlan.build(cluster, raw_output)
    except MetadataError as e:
        error(f"Agent output rejected: {e}")
        return 1

    if not working_tree_has_changes():
        warning(
            "Empty diff for cluster; agent decided no edit needed. "
            "Comment(s) remain unresolved."
        )
        return 0

    bad = policy_violations()
    if bad:
        error("Agent modified disallowed paths; aborting cluster:")
        for p in bad:
            print(f"  {p}", file=sys.stderr)
        git("checkout", "--", ".")
        return 1

    session = BotSession.open(token=app_token, app_slug=app_slug, repo=repo)
    base = session.default_branch()

    git("checkout", "-b", plan.branch)
    session.commit(subject=plan.title, body=plan.body)

    try:
        session.push(f"HEAD:refs/heads/{plan.branch}")
    except subprocess.CalledProcessError:
        return 2

    _ensure_labels(session, plan.labels)
    labels = ",".join(plan.labels)
    reviewers = ",".join(plan.reviewers)

    try:
        session.gh(
            [
                "pr", "create",
                "--base", base,
                "--head", plan.branch,
                "--title", plan.title,
                "--body", plan.body,
                "--label", labels,
                "--reviewer", reviewers,
            ]
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
