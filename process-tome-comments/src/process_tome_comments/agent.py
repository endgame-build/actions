"""Configure pi, build the per-cluster prompt, invoke pi inside nono, capture output.

Three previously-separate scripts collapse here as internal helpers. The
``run`` entry point is what the workflow invokes; each helper is importable
for tests.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

from .comments import Cluster
from .gha import error

DEFAULT_MODEL = "gpt-oss:120b"

#: Sparse-checkout location of the actions repo inside the consumer's
#: checkout. Set by the workflow's checkout step (``path: .actions``).
ACTIONS_PATH = Path(".actions/process-tome-comments")

PRELUDE_PATH = ACTIONS_PATH / "prompt" / "prelude.md"
PROFILE_PATH = ACTIONS_PATH / "profiles" / "pi.json"


# ── pi configuration ──────────────────────────────────────────────────────


def write_pi_config(model_id: str, *, home: Path | None = None) -> None:
    """Write ``~/.pi/agent/{models.json,settings.json}`` so pi knows about Ollama Cloud.

    Pi v0.74 requires custom-provider registration in ``~/.pi/agent/models.json``
    (per ``docs/models.md``); project-local ``.pi/settings.json`` does NOT
    accept the ``providers`` map. We also write a minimal global
    ``settings.json`` pinning defaultProvider/defaultModel and the
    ``enabledModels`` allowlist, which gates which models pi will use.
    """
    pi_agent_dir = (home or Path(os.environ.get("HOME", "~")).expanduser()) / ".pi" / "agent"
    pi_agent_dir.mkdir(parents=True, exist_ok=True)

    models_config = {
        "providers": {
            "ollama-cloud": {
                "name": "Ollama Cloud",
                "baseUrl": "https://ollama.com/v1",
                "api": "openai-completions",
                "apiKey": "OLLAMA_API_KEY",
                "compat": {
                    "supportsDeveloperRole": False,
                    "supportsReasoningEffort": False,
                },
                "models": [{"id": model_id}],
            },
        },
    }
    (pi_agent_dir / "models.json").write_text(
        json.dumps(models_config, indent=2), encoding="utf-8"
    )

    settings_config = {
        "defaultProvider": "ollama-cloud",
        "defaultModel": model_id,
        "enabledModels": [f"ollama-cloud/{model_id}"],
    }
    (pi_agent_dir / "settings.json").write_text(
        json.dumps(settings_config, indent=2), encoding="utf-8"
    )


# ── prompt assembly ───────────────────────────────────────────────────────


def build_prompt(cluster: Cluster, prelude_text: str) -> str:
    """Compose the per-cluster prompt: prelude + cluster context + footer."""
    comment_ids = ", ".join(cluster.comment_ids)
    parts: list[str] = [prelude_text]

    parts.append(
        f"""

---

## Cluster context for THIS invocation

**Source file:** `{cluster.file_path}`
**Block index:** {cluster.block_index}
**Cluster size:** {len(cluster.comments)} comment(s)
**CLUSTER_COMMENT_IDS:** {comment_ids}

The comments to address (in arrival order):

"""
    )

    for c in cluster.comments:
        parts.append(
            f"### Comment `{c.id}` by @{c.author_login} ({c.created_at})\n\n{c.body}\n\n"
        )

    parts.append(
        """
## What to do now

1. Read `.tome/comments.jsonl` to confirm the comment bodies match what's shown above (the workflow may stage stale data; the file is the source of truth).
2. Read the source file at the path above.
3. Apply the requested change(s) using the `edit` or `write` tool.
4. Emit the final JSON object as specified in ACTION B above. Bare JSON only — no markdown fence, no narration.

Remember: do NOT modify `.tome/comments.jsonl`, `.github/`, or any CI configuration. Do NOT include the literal string `@claude` in your output (paraphrase as `@-claude` if needed).
"""
    )
    return "".join(parts)


# ── agent invocation ──────────────────────────────────────────────────────


def invoke_pi(prompt: str, *, model_id: str, profile_path: Path) -> subprocess.CompletedProcess[str]:
    """Run ``nono run --profile <profile> --allow-cwd -- pi -p --mode json …``.

    The profile's ``workdir.access: readwrite`` declares intent; ``--allow-cwd``
    is still required at invocation time to actually grant access (per nono
    v0.53 — the flag is the explicit confirmation that we want the current
    directory included).
    """
    cmd = [
        "nono", "run",
        "--profile", str(profile_path.resolve()),
        "--allow-cwd",
        "--",
        "pi", "-p", "--mode", "json",
        "--provider", "ollama-cloud",
        "--model", f"ollama-cloud/{model_id}",
        prompt,
    ]
    return subprocess.run(cmd, capture_output=True, text=True, check=False)


def extract_last_assistant_text(stdout: str) -> str | None:
    """Walk pi's ``--mode json`` event stream; return the last assistant ``message_end``'s text."""
    last: str | None = None
    for line in stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if event.get("type") != "message_end":
            continue
        msg = event.get("message", {})
        if msg.get("role") != "assistant":
            continue
        content = msg.get("content")
        if isinstance(content, str):
            last = content
        elif isinstance(content, list):
            parts = [
                b.get("text", "")
                for b in content
                if isinstance(b, dict) and b.get("type") == "text"
            ]
            if parts:
                last = "".join(parts)
    return last


# ── subcommand entry point ────────────────────────────────────────────────


def main() -> int:
    runner_temp = Path(os.environ.get("RUNNER_TEMP", "/tmp"))
    matrix_idx = os.environ.get("MATRIX_IDX", "0")
    cluster_file = runner_temp / "clusters" / f"{matrix_idx}.json"
    if not cluster_file.exists():
        error(f"Cluster JSON not found: {cluster_file}")
        return 1

    model_id = os.environ.get("AUTOFIX_MODEL", DEFAULT_MODEL) or DEFAULT_MODEL
    write_pi_config(model_id)

    cluster = Cluster.from_json_file(cluster_file)
    prelude = PRELUDE_PATH.read_text(encoding="utf-8")
    prompt = build_prompt(cluster, prelude)
    prompt_path = runner_temp / "cluster-prompt.md"
    prompt_path.write_text(prompt, encoding="utf-8")
    print(f"Prompt size: {len(prompt)} chars")

    if not PROFILE_PATH.exists():
        error(f"nono profile not found at {PROFILE_PATH}")
        return 1

    proc = invoke_pi(prompt, model_id=model_id, profile_path=PROFILE_PATH)

    # Persist raw output for forensics regardless of outcome.
    (runner_temp / "pi-stdout.jsonl").write_text(proc.stdout, encoding="utf-8")
    (runner_temp / "pi-stderr.log").write_text(proc.stderr, encoding="utf-8")

    if proc.returncode != 0:
        error(f"pi exited {proc.returncode}")
        print(proc.stderr[-2000:], file=sys.stderr)
        return proc.returncode

    last_text = extract_last_assistant_text(proc.stdout)
    if last_text is None:
        error("Could not find any assistant message_end event in pi output")
        return 1

    out_path = runner_temp / "agent-output.txt"
    out_path.write_text(last_text, encoding="utf-8")
    print(f"Captured {len(last_text)} chars to {out_path}")

    gha_output_path = os.environ.get("GITHUB_OUTPUT")
    if gha_output_path:
        with open(gha_output_path, "a", encoding="utf-8") as f:
            f.write(f"agent_output_path={out_path}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
