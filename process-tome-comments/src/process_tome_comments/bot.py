"""BotSession: ``tome-comments[bot]`` identity bound to a repo, with git+gh helpers."""

from __future__ import annotations

import os
import subprocess
from dataclasses import dataclass
from typing import Sequence

from .gha import error, git, run


EXPECTED_BOT_LOGIN = "tome-comments[bot]"


@dataclass(frozen=True)
class BotIdentity:
    login: str
    email: str
    token: str


class BotSession:
    """Constructing a session applies ``git config user.{name,email}`` as a side effect."""

    def __init__(self, identity: BotIdentity, *, repo: str) -> None:
        self.identity = identity
        self.repo = repo
        git("config", "user.name", identity.login)
        git("config", "user.email", identity.email)

    @classmethod
    def open(
        cls,
        *,
        token: str,
        app_slug: str,
        repo: str,
        expected_login: str = EXPECTED_BOT_LOGIN,
    ) -> BotSession:
        # If the App slug doesn't derive to the expected login, downstream
        # listeners that filter on bot-authored commits won't match. Fail at
        # setup time rather than silently producing wrong-author commits.
        derived = f"{app_slug}[bot]"
        if derived != expected_login:
            error(
                f"App login {derived!r} != expected {expected_login!r}. "
                "Either rename the App so its slug matches, or update "
                "EXPECTED_BOT_LOGIN."
            )
            raise SystemExit(1)
        # GitHub's noreply email is `<numeric id>+<login>@users.noreply.github.com`.
        # Installation tokens can't read /users/<login>, so use the host GITHUB_TOKEN.
        host_gh_token = os.environ.get("GITHUB_TOKEN")
        env = {"GH_TOKEN": host_gh_token} if host_gh_token else None
        r = run(["gh", "api", f"users/{derived}", "--jq", ".id"], env=env)
        numeric_id = r.stdout.strip()
        email = f"{numeric_id}+{derived}@users.noreply.github.com"
        return cls(BotIdentity(login=derived, email=email, token=token), repo=repo)

    def commit(self, *, subject: str, body: str | None = None) -> None:
        if body:
            git("commit", "-m", subject, "-m", body)
        else:
            git("commit", "-m", subject)

    def push(self, refspec: str) -> None:
        # Pushes by the runner's GITHUB_TOKEN identity don't fire pull_request
        # events; the App-token identity does. Credential-baked URL forces the
        # App identity even when origin is configured with a different token.
        url = f"https://x-access-token:{self.identity.token}@github.com/{self.repo}.git"
        try:
            run(["git", "push", url, refspec])
        except subprocess.CalledProcessError as e:
            error(f"git push failed: {e.stderr}")
            raise

    def gh(self, args: Sequence[str]) -> subprocess.CompletedProcess[str]:
        return run(["gh", *args], env={"GH_TOKEN": self.identity.token})

    def default_branch(self) -> str:
        r = self.gh(["api", f"repos/{self.repo}", "--jq", ".default_branch"])
        return r.stdout.strip()
