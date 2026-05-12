"""GitHub Actions glue: outputs, notice/warning/error formatting, subprocess wrappers.

Pure helpers. No domain logic. Imported by every subcommand.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any


def gha_output(key: str, value: str) -> None:
    """Append ``key=value`` to ``$GITHUB_OUTPUT``. Falls back to stdout when unset (local runs)."""
    path = os.environ.get("GITHUB_OUTPUT")
    if not path:
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


def run(
    cmd: list[str],
    *,
    check: bool = True,
    capture: bool = True,
    env: dict[str, str] | None = None,
    cwd: str | Path | None = None,
    stdin: str | None = None,
) -> subprocess.CompletedProcess[str]:
    """Thin wrapper around ``subprocess.run`` with text I/O and inherited env merging."""
    return subprocess.run(
        cmd,
        check=check,
        text=True,
        capture_output=capture,
        env={**os.environ, **(env or {})},
        cwd=cwd,
        input=stdin,
    )


def gh_json(args: list[str], default: Any = None, *, token: str | None = None) -> Any:
    """Run ``gh <args>`` and parse stdout as JSON. Returns ``default`` on error."""
    env = {"GH_TOKEN": token} if token else None
    try:
        r = run(["gh", *args], env=env)
        return json.loads(r.stdout)
    except (subprocess.CalledProcessError, json.JSONDecodeError):
        return default


def git(*args: str, check: bool = True, capture: bool = True) -> subprocess.CompletedProcess[str]:
    return run(["git", *args], check=check, capture=capture)
