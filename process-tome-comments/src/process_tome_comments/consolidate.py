"""``consolidate`` subcommand: post-merge JSONL update.

Triggered by ``pull_request: closed``. If the closed PR was merged and carries
``tome-comment-id:*`` labels, marks those comments resolved in
``.tome/comments.jsonl`` on the default branch via a separate bot commit.

Inputs (env): ``PR_NUMBER``, ``PR_MERGED``, ``APP_TOKEN``, ``APP_SLUG``,
``GITHUB_REPOSITORY``.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import subprocess
from pathlib import Path

from .bot import BotSession
from .comments import load_comments, write_comments
from .gha import error, git, notice, warning
from .metadata import TOME_PR_LABEL, comment_ids_from_labels


def resolve_comments_on_disk(jsonl_path: Path, comment_ids: set[str], *, by: str, at: str) -> int:
    comments = load_comments(jsonl_path)
    if not comments:
        return 0
    changed = 0
    out = []
    for c in comments:
        if c.id in comment_ids and not c.is_resolved:
            out.append(c.resolved(by=by, at=at))
            changed += 1
        else:
            out.append(c)
    if changed:
        write_comments(jsonl_path, out)
    return changed


def main() -> int:
    pr_number = os.environ["PR_NUMBER"]
    pr_merged = os.environ["PR_MERGED"].lower() == "true"
    app_token = os.environ["APP_TOKEN"]
    app_slug = os.environ["APP_SLUG"]
    repo = os.environ["GITHUB_REPOSITORY"]

    if not pr_merged:
        print(
            f"PR #{pr_number} closed without merge; safety-net filter handles "
            "re-run loop, no JSONL update."
        )
        return 0

    session = BotSession.open(token=app_token, app_slug=app_slug, repo=repo)

    labels_json = session.gh(["pr", "view", pr_number, "--json", "labels"]).stdout
    labels = json.loads(labels_json).get("labels", [])
    comment_ids = comment_ids_from_labels(labels)
    if not comment_ids:
        print(f"PR #{pr_number} has no tome-comment-id labels; not a tome PR.")
        return 0

    print(f"Resolving comment(s) on merge of PR #{pr_number}:")
    for cid in comment_ids:
        print(f"  {cid}")

    jsonl_path = Path(".tome/comments.jsonl")
    if not jsonl_path.exists():
        warning(f"PR #{pr_number} merged but .tome/comments.jsonl no longer exists.")
        return 0

    now = dt.datetime.now(dt.UTC).strftime("%Y-%m-%dT%H:%M:%S.000Z")
    n_changed = resolve_comments_on_disk(
        jsonl_path, set(comment_ids), by=session.identity.login, at=now
    )
    if n_changed == 0:
        warning("No JSONL changes after transform — comments may already be resolved.")
        return 0

    base = session.default_branch()

    git("add", ".tome/comments.jsonl")

    short_ids = ",".join(cid[:8] for cid in comment_ids)
    if len(comment_ids) == 1:
        subject = f"chore(tome): resolve comment {short_ids}"
    else:
        subject = f"chore(tome): resolve {len(comment_ids)} comments ({short_ids})"
    session.commit(subject=subject, body=f"Resolved by merge of #{pr_number}.")

    try:
        session.push(f"HEAD:{base}")
    except Exception as e:
        error(f"push failed: {e}")
        return 1

    # Drop the common label LAST. If this fails, idempotency still holds via
    # the jsonl flip we just pushed; the orphaned label is cosmetic.
    try:
        session.gh(["pr", "edit", pr_number, "--remove-label", TOME_PR_LABEL])
    except subprocess.CalledProcessError as e:
        warning(f"could not drop {TOME_PR_LABEL} from PR #{pr_number}: {e.stderr}")

    notice(f"Resolved {n_changed} comment(s) on {base}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
