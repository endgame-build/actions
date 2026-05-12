"""GitHub App-bot identity + credential-baked git operations.

Single source of truth for how the ``tome-comments[bot]`` identity is
resolved, how App-minted tokens are used to push, and how to fail loudly
when the App slug doesn't match the expected name.

Replaces three previously-duplicated patterns:

- ``Resolve App bot identity`` shell step (was duplicated in process and
  consolidate jobs of the workflow YAML)
- The ``https://x-access-token:${APP_TOKEN}@...`` push-URL construction
  (was duplicated in ``snapshot_and_pr`` and ``consolidate``)
- The ``git config user.name/email`` calls (was duplicated in the same
  two scripts)
"""

from __future__ import annotations

import os
import subprocess
from dataclasses import dataclass
from typing import Sequence

from .gha import error, git, run


EXPECTED_BOT_LOGIN = "tome-comments[bot]"


@dataclass(frozen=True)
class BotIdentity:
    """The App-bot's git identity.

    Constructed via :meth:`resolve` from a freshly-minted App token; or
    constructed directly in tests with arbitrary values.
    """

    login: str
    email: str
    token: str

    @classmethod
    def resolve(
        cls,
        *,
        token: str,
        app_slug: str,
        expected_login: str = EXPECTED_BOT_LOGIN,
    ) -> "BotIdentity":
        """Derive the bot's login + noreply email from the App slug.

        Fails loudly if the derived login doesn't match ``expected_login``. The
        canonical example: the App is named ``tome-comments`` in the GitHub
        UI but its slug came out as ``tome-comments-bot``; the workflow would
        be silently broken (gate 8 of agent-pr-fix wouldn't match the actual
        commits as bot commits). Fail at setup time.
        """
        derived = f"{app_slug}[bot]"
        if derived != expected_login:
            error(
                f"App login {derived!r} != expected {expected_login!r}. "
                "Either rename the App so its slug matches, or update "
                "EXPECTED_BOT_LOGIN."
            )
            raise SystemExit(1)
        # GitHub's noreply email for App bots is `<numeric id>+<login>@users.noreply.github.com`.
        # The id comes from /users/<login>. We deliberately use the host GITHUB_TOKEN here,
        # not the App token: installation tokens can't read /user-level resources.
        host_gh_token = os.environ.get("GITHUB_TOKEN")
        env = {"GH_TOKEN": host_gh_token} if host_gh_token else None
        r = run(["gh", "api", f"users/{derived}", "--jq", ".id"], env=env)
        numeric_id = r.stdout.strip()
        email = f"{numeric_id}+{derived}@users.noreply.github.com"
        return cls(login=derived, email=email, token=token)


def configure_git_identity(identity: BotIdentity) -> None:
    """Set ``user.name`` and ``user.email`` for subsequent git commits."""
    git("config", "user.name", identity.login)
    git("config", "user.email", identity.email)


def commit(*, subject: str, body: str | None = None) -> None:
    """Create a commit on the current branch. Caller is responsible for staging."""
    if body:
        git("commit", "-m", subject, "-m", body)
    else:
        git("commit", "-m", subject)


def push(
    identity: BotIdentity,
    *,
    repo: str,
    refspec: str,
) -> None:
    """Push using a credential-baked URL so GitHub fires the right events.

    ``refspec`` is a normal git push refspec, e.g. ``"HEAD:refs/heads/foo"``
    or ``"HEAD:main"``.

    Why a credential-baked URL: the runner's ``origin`` may be configured
    with the host ``GITHUB_TOKEN``, but pushes by that identity are
    intentionally suppressed by GitHub from firing ``pull_request:opened``
    or ``pull_request:synchronize`` events. The App-token identity fires
    those events normally.
    """
    url = f"https://x-access-token:{identity.token}@github.com/{repo}.git"
    try:
        run(["git", "push", url, refspec])
    except subprocess.CalledProcessError as e:
        error(f"git push failed: {e.stderr}")
        raise


def gh(args: Sequence[str], identity: BotIdentity) -> subprocess.CompletedProcess[str]:
    """Run ``gh <args>`` with ``GH_TOKEN`` set to the App token."""
    return run(["gh", *args], env={"GH_TOKEN": identity.token})


def default_branch(identity: BotIdentity, repo: str) -> str:
    """Look up the repo's default branch via the GitHub API."""
    r = gh(["api", f"repos/{repo}", "--jq", ".default_branch"], identity)
    return r.stdout.strip()
