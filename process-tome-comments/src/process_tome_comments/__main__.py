"""Subcommand dispatcher.

Invoked from the workflow as ``python -m process_tome_comments <subcommand>``.
"""

from __future__ import annotations

import sys

from . import agent, consolidate, prepare, pr_open


SUBCOMMANDS = {
    "prepare": prepare.main,
    "agent": agent.main,
    "pr-open": pr_open.main,
    "consolidate": consolidate.main,
}


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in SUBCOMMANDS:
        print(f"usage: python -m process_tome_comments {{{','.join(SUBCOMMANDS)}}}", file=sys.stderr)
        return 2
    return SUBCOMMANDS[sys.argv[1]]()


if __name__ == "__main__":
    raise SystemExit(main())
