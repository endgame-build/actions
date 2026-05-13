"""PiAgent: address a Cluster via pi-coding-agent inside the nono sandbox."""

from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path

from .comments import Cluster
from .gha import run

DEFAULT_MODEL = "gpt-oss:120b"
OLLAMA_PROVIDER_ID = "ollama-cloud"


@dataclass(frozen=True)
class PiInvocation:
    returncode: int
    stdout: str
    stderr: str


@dataclass(frozen=True)
class AgentResult:
    invocation: PiInvocation
    prompt: str
    assistant_text: str


class AgentError(RuntimeError):
    """``invocation`` is set when failure happened post-subprocess; ``None`` otherwise."""

    def __init__(self, message: str, invocation: PiInvocation | None = None) -> None:
        super().__init__(message)
        self.invocation = invocation


class PiAgent:
    def __init__(
        self,
        *,
        model_id: str,
        profile_path: Path,
        prelude_text: str,
    ) -> None:
        self.model_id = model_id
        self.profile_path = profile_path
        self.prelude_text = prelude_text

    def address(self, cluster: Cluster) -> AgentResult:
        self._write_provider_config()
        prompt = self._build_prompt(cluster)
        inv = self._invoke(prompt)
        if inv.returncode != 0:
            raise AgentError(f"pi exited {inv.returncode}", invocation=inv)
        text = _extract_last_assistant_text(inv.stdout)
        if text is None:
            raise AgentError(
                "no assistant message_end event in pi output", invocation=inv
            )
        return AgentResult(invocation=inv, prompt=prompt, assistant_text=text)

    def _build_prompt(self, cluster: Cluster) -> str:
        comment_ids = ", ".join(cluster.comment_ids)
        parts: list[str] = [self.prelude_text]

        location = f"**Block index:** {cluster.block_index}"
        if cluster.line_start is not None and cluster.line_end is not None:
            location += (
                f" (lines {cluster.line_start}–{cluster.line_end} in the current"
                " file; the snippet is shown below, but the file is the source"
                " of truth — re-read if anything looks off)"
            )

        snippet_block = ""
        if cluster.block_snippet:
            snippet_block = (
                "\n**Block snippet (the text the comment anchors to):**\n\n"
                f"```\n{cluster.block_snippet}\n```\n"
            )

        parts.append(
            f"""

---

## Cluster context for THIS invocation

**Source file:** `{cluster.file_path}`
{location}
**Cluster size:** {len(cluster.comments)} comment(s)
**CLUSTER_COMMENT_IDS:** {comment_ids}
{snippet_block}
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

    def _write_provider_config(self) -> None:
        # Pi v0.74 requires custom-provider registration in ~/.pi/agent/models.json
        # (per docs/models.md); a project-local .pi/settings.json does NOT accept
        # the providers map. settings.json gates enabledModels.
        pi_agent_dir = Path(os.environ.get("HOME", "~")).expanduser() / ".pi" / "agent"
        pi_agent_dir.mkdir(parents=True, exist_ok=True)

        models_config = {
            "providers": {
                OLLAMA_PROVIDER_ID: {
                    "name": "Ollama Cloud",
                    "baseUrl": "https://ollama.com/v1",
                    "api": "openai-completions",
                    "apiKey": "OLLAMA_API_KEY",
                    "compat": {
                        "supportsDeveloperRole": False,
                        "supportsReasoningEffort": False,
                    },
                    "models": [{"id": self.model_id}],
                },
            },
        }
        (pi_agent_dir / "models.json").write_text(
            json.dumps(models_config, indent=2), encoding="utf-8"
        )

        settings_config = {
            "defaultProvider": OLLAMA_PROVIDER_ID,
            "defaultModel": self.model_id,
            "enabledModels": [f"{OLLAMA_PROVIDER_ID}/{self.model_id}"],
        }
        (pi_agent_dir / "settings.json").write_text(
            json.dumps(settings_config, indent=2), encoding="utf-8"
        )

    def _invoke(self, prompt: str) -> PiInvocation:
        # nono v0.53: profile's workdir.access declares intent, but --allow-cwd
        # is still required at invocation time to actually grant access.
        cmd = [
            "nono", "run",
            "--profile", str(self.profile_path.resolve()),
            "--allow-cwd",
            "--",
            "pi", "-p", "--mode", "json",
            "--provider", OLLAMA_PROVIDER_ID,
            "--model", f"{OLLAMA_PROVIDER_ID}/{self.model_id}",
            prompt,
        ]
        proc = run(cmd, check=False)
        return PiInvocation(
            returncode=proc.returncode, stdout=proc.stdout, stderr=proc.stderr
        )


def _extract_last_assistant_text(stdout: str) -> str | None:
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
