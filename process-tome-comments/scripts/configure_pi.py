#!/usr/bin/env python3
"""Write a project-local pi config that points at Ollama Cloud.

The config goes to `.pi/settings.json` in the cwd (which is the consumer
repo's working tree). pi reads this config in addition to the global
`~/.pi/agent/settings.json`.

Inputs (env):
    AUTOFIX_MODEL - the Ollama Cloud model id (e.g. 'gpt-oss:120b'). Defaults
                    to 'gpt-oss:120b'.
"""

from __future__ import annotations

import json
import os
from pathlib import Path


# Ollama Cloud exposes an OpenAI-compatible endpoint at the same hostname.
# The API key is read from env via the literal string "OLLAMA_API_KEY" — pi
# resolves env var names in the apiKey field.
DEFAULT_MODEL = "gpt-oss:120b"


def main() -> int:
    model_id = os.environ.get("AUTOFIX_MODEL", DEFAULT_MODEL) or DEFAULT_MODEL

    config = {
        "providers": {
            "ollama-cloud": {
                "name": "Ollama Cloud",
                "baseUrl": "https://ollama.com/v1",
                "api": "openai-completions",
                "apiKey": "OLLAMA_API_KEY",  # pi reads this env var at request time
                "compat": {
                    "supportsDeveloperRole": False,
                    "supportsReasoningEffort": False,
                },
                "models": [
                    {"id": model_id},
                ],
            },
        },
        "defaults": {
            "model": f"ollama-cloud/{model_id}",
        },
    }

    pi_dir = Path(".pi")
    pi_dir.mkdir(exist_ok=True)
    settings_path = pi_dir / "settings.json"
    settings_path.write_text(json.dumps(config, indent=2), encoding="utf-8")

    print(f"Wrote {settings_path} pinning provider=ollama-cloud model={model_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
