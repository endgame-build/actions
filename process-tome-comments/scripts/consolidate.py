#!/usr/bin/env python3
"""Post-merge listener: mark a merged PR's addressed comments as resolved.

Inputs (env):
    PR_NUMBER         - the closed PR number (from github.event.pull_request.number)
    PR_MERGED         - "true" if merged, "false" if just closed
    APP_TOKEN         - tome-comments[bot] App token
    BOT_LOGIN         - bot login
    BOT_EMAIL         - bot commit email
    GITHUB_REPOSITORY - owner/repo

Behavior:
    1. If PR was not merged, exit 0 (closed-not-merged is the Q2 safety-net signal).
    2. Read all tome-comment-id:<uuid> labels on the PR.
    3. If no such labels, exit 0 (not a tome PR).
    4. Update .tome/comments.jsonl: for each id, set isResolved=true,
       resolvedBy=BOT_LOGIN, resolvedAt=<ISO now>.
    5. Commit and push to default branch.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import subprocess
import sys
from pathlib import Path

from _common import error, git, notice, run, warning


def main() -> int:
    pr_number = os.environ["PR_NUMBER"]
    pr_merged = os.environ["PR_MERGED"].lower() == "true"
    app_token = os.environ["APP_TOKEN"]
    bot_login = os.environ["BOT_LOGIN"]
    bot_email = os.environ["BOT_EMAIL"]
    repo = os.environ["GITHUB_REPOSITORY"]

    if not pr_merged:
        print(f"PR #{pr_number} closed without merge; safety-net filter handles "
              "re-run loop, no JSONL update.")
        return 0

    # Read labels via gh
    labels_json = run(
        ["gh", "pr", "view", pr_number, "--json", "labels"],
        env={"GH_TOKEN": app_token},
    ).stdout
    labels = json.loads(labels_json).get("labels", [])
    comment_ids = [
        name.removeprefix("tome-comment-id:")
        for label in labels
        if (name := label.get("name", "")).startswith("tome-comment-id:")
    ]
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

    target_ids = set(comment_ids)
    new_lines: list[str] = []
    n_changed = 0
    for line in jsonl_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        d = json.loads(line)
        if d["id"] in target_ids and not d.get("isResolved", False):
            d["isResolved"] = True
            d["resolvedBy"] = bot_login
            d["resolvedAt"] = now
            d["updatedAt"] = now
            n_changed += 1
        new_lines.append(json.dumps(d, ensure_ascii=False, separators=(",", ":")))

    jsonl_path.write_text("\n".join(new_lines) + "\n", encoding="utf-8")

    if n_changed == 0:
        warning("No JSONL changes after transform — comments may already be resolved.")
        return 0

    # Commit + push
    git("config", "user.name", bot_login)
    git("config", "user.email", bot_email)

    default_branch = run(
        ["gh", "api", f"repos/{repo}", "--jq", ".default_branch"],
        env={"GH_TOKEN": app_token},
    ).stdout.strip()

    git("add", ".tome/comments.jsonl")
    r = git("diff", "--cached", "--quiet", check=False)
    if r.returncode == 0:
        warning("No staged changes after add — unexpected; skipping commit.")
        return 0

    short_ids = ",".join(cid[:8] for cid in comment_ids)
    if len(comment_ids) == 1:
        subject = f"chore(tome): resolve comment {short_ids}"
    else:
        subject = f"chore(tome): resolve {len(comment_ids)} comments ({short_ids})"

    git("commit", "-m", subject, "-m", f"Resolved by merge of #{pr_number}.")

    push_url = f"https://x-access-token:{app_token}@github.com/{repo}.git"
    try:
        run(["git", "push", push_url, f"HEAD:{default_branch}"])
    except subprocess.CalledProcessError as e:
        error(f"git push failed: {e.stderr}")
        return 1

    notice(f"Resolved {n_changed} comment(s) on {default_branch}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
