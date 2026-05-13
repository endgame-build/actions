"""``agent`` subcommand: load cluster, run PiAgent, persist outputs."""

from __future__ import annotations

import os
import sys
from pathlib import Path

from .comments import Cluster
from .gha import error
from .pi_agent import DEFAULT_MODEL, AgentError, PiAgent, PiInvocation


# Sparse-checkout location of the actions repo inside the consumer's checkout.
# Set by the workflow's checkout step (path: .actions).
ACTIONS_PATH = Path(".actions/process-tome-comments")

PRELUDE_PATH = ACTIONS_PATH / "prompt" / "prelude.md"
PROFILE_PATH = ACTIONS_PATH / "profiles" / "pi.json"


def _persist_invocation(invocation: PiInvocation, runner_temp: Path) -> None:
    (runner_temp / "pi-stdout.jsonl").write_text(invocation.stdout, encoding="utf-8")
    (runner_temp / "pi-stderr.log").write_text(invocation.stderr, encoding="utf-8")


def main() -> int:
    runner_temp = Path(os.environ.get("RUNNER_TEMP", "/tmp"))
    matrix_idx = os.environ.get("MATRIX_IDX", "0")
    cluster_file = runner_temp / "clusters" / f"{matrix_idx}.json"
    if not cluster_file.exists():
        error(f"Cluster JSON not found: {cluster_file}")
        return 1

    model_id = os.environ.get("AUTOFIX_MODEL", DEFAULT_MODEL) or DEFAULT_MODEL
    cluster = Cluster.from_json_file(cluster_file)

    agent = PiAgent(
        model_id=model_id,
        profile_path=PROFILE_PATH,
        prelude_text=PRELUDE_PATH.read_text(encoding="utf-8"),
    )

    try:
        result = agent.address(cluster)
    except AgentError as e:
        if e.invocation is not None:
            _persist_invocation(e.invocation, runner_temp)
            print(e.invocation.stderr[-2000:], file=sys.stderr)
        error(str(e))
        return 1

    _persist_invocation(result.invocation, runner_temp)

    prompt_path = runner_temp / "cluster-prompt.md"
    prompt_path.write_text(result.prompt, encoding="utf-8")
    print(f"Prompt size: {len(result.prompt)} chars")

    out_path = runner_temp / "agent-output.txt"
    out_path.write_text(result.assistant_text, encoding="utf-8")
    print(f"Captured {len(result.assistant_text)} chars to {out_path}")

    gha_output_path = os.environ.get("GITHUB_OUTPUT")
    if gha_output_path:
        with open(gha_output_path, "a", encoding="utf-8") as f:
            f.write(f"agent_output_path={out_path}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
