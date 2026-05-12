#!/usr/bin/env python3
"""Invoke pi on the per-cluster prompt and capture the final assistant text.

Inputs (env):
    RUNNER_TEMP    - GHA runner temp dir
    OLLAMA_API_KEY - already in env (set by workflow); pi reads it for the
                     ollama-cloud provider configured in .pi/settings.json
    GITHUB_OUTPUT  - workflow output file (we write `agent_output_path` so
                     snapshot_and_pr.py can read it).

Behavior:
    1. Read ${RUNNER_TEMP}/cluster-prompt.md.
    2. Run `pi -p --mode json --model ollama-cloud/<model>` with the prompt
       piped to stdin. (Alternative: `pi -p "<prompt>"`, but with --mode json
       we get a structured event stream we can robustly parse.)
    3. Walk the event stream; find the last `message_end` event whose message
       has role == "assistant" and contains a text block; write its concatenated
       text to ${RUNNER_TEMP}/agent-output.txt.
    4. Emit `agent_output_path` to GITHUB_OUTPUT.

Failure modes are surfaced as exceptions; the workflow's matrix step fails
(`fail-fast: false`) and other clusters proceed.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path


def main() -> int:
    runner_temp = Path(os.environ.get("RUNNER_TEMP", "/tmp"))
    prompt_file = runner_temp / "cluster-prompt.md"
    if not prompt_file.exists():
        print(f"::error::Prompt file not found: {prompt_file}", file=sys.stderr)
        return 1

    prompt = prompt_file.read_text(encoding="utf-8")

    # pi -p (--print) prints the final response and exits. --mode json emits
    # the event stream so we can robustly parse the last assistant message
    # without depending on stdout formatting.
    #
    # nono is the unconditional sandbox boundary. The profile lives in
    # process-tome-comments/profiles/pi.json (sparse-checked-out into
    # `.actions/`); it restricts the agent to the working tree + ~/.pi state,
    # network to ollama.com only, and passes only OLLAMA_API_KEY through.
    profile_path = Path(".actions/process-tome-comments/profiles/pi.json").resolve()
    if not profile_path.exists():
        print(f"::error::nono profile not found at {profile_path}", file=sys.stderr)
        return 1

    # Pass --provider/--model explicitly. The project-local .pi/settings.json
    # also pins these, but CLI flags are the most predictable override and
    # neutralize any global pi config the runner may have.
    model_id = os.environ.get("AUTOFIX_MODEL", "gpt-oss:120b")
    cmd = [
        "nono", "run",
        "--profile", str(profile_path),
        "--",
        "pi", "-p", "--mode", "json",
        "--provider", "ollama-cloud",
        "--model", f"ollama-cloud/{model_id}",
        prompt,
    ]

    proc = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        check=False,
    )

    # Persist raw output for forensics regardless of outcome.
    (runner_temp / "pi-stdout.jsonl").write_text(proc.stdout, encoding="utf-8")
    (runner_temp / "pi-stderr.log").write_text(proc.stderr, encoding="utf-8")

    if proc.returncode != 0:
        print(f"::error::pi exited {proc.returncode}", file=sys.stderr)
        print(proc.stderr[-2000:], file=sys.stderr)
        return proc.returncode

    # Walk events, find the last assistant message's text content.
    last_assistant_text: str | None = None
    for line in proc.stdout.splitlines():
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
        # message.content may be a string or a list of blocks (text/tool_use).
        content = msg.get("content")
        if isinstance(content, str):
            last_assistant_text = content
        elif isinstance(content, list):
            text_parts = [
                block.get("text", "")
                for block in content
                if isinstance(block, dict) and block.get("type") == "text"
            ]
            if text_parts:
                last_assistant_text = "".join(text_parts)

    if last_assistant_text is None:
        print("::error::Could not find any assistant message_end event in pi output",
              file=sys.stderr)
        return 1

    out_path = runner_temp / "agent-output.txt"
    out_path.write_text(last_assistant_text, encoding="utf-8")
    print(f"Captured {len(last_assistant_text)} chars to {out_path}")

    gha_output = os.environ.get("GITHUB_OUTPUT")
    if gha_output:
        with open(gha_output, "a", encoding="utf-8") as f:
            f.write(f"agent_output_path={out_path}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
