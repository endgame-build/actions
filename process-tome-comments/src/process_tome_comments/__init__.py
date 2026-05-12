"""Process Tome review comments by opening one PR per cluster.

Subcommand dispatcher lives in ``__main__``; per-subcommand entry points live
in :mod:`process_tome_comments.cli`. Core domain types
(:class:`~process_tome_comments.comments.Comment`,
:class:`~process_tome_comments.comments.Cluster`) and helpers
(:mod:`process_tome_comments.bot_git`,
:mod:`process_tome_comments.metadata`) are exposed for direct import in tests.
"""

from __future__ import annotations
