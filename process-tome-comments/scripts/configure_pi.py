#!/usr/bin/env python3
"""Write the pi provider config so pi can talk to Ollama Cloud.

Per pi's docs (docs/models.md), custom providers (Ollama, vLLM, etc.) are
registered via `~/.pi/agent/models.json`. There is no project-local
equivalent for custom-provider registration in pi v0.74; settings.json
under `.pi/` accepts a handful of overrides but not the `providers` map.

We write this file from outside the sandbox so it's already in place
when nono+pi start. The nono profile allows `$HOME/.pi` (recursive).

Inputs (env):
    AUTOFIX_MODEL - the Ollama Cloud model id (e.g. 'gpt-oss:120b'). Defaults
                    to 'gpt-oss:120b'.
    HOME          - resolved from env to locate ~/.pi/agent/.
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

    models_config = {
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
    }

    pi_agent_dir = Path(os.environ.get("HOME", "~")).expanduser() / ".pi" / "agent"
    pi_agent_dir.mkdir(parents=True, exist_ok=True)
    models_path = pi_agent_dir / "models.json"
    models_path.write_text(json.dumps(models_config, indent=2), encoding="utf-8")

    # Also write a minimal settings.json. The `enabledModels` allowlist gates
    # which models pi will use; without our model in it, pi may refuse even
    # with --model flag. defaultProvider/defaultModel set the fallback if the
    # CLI flags are ever omitted.
    settings_config = {
        "defaultProvider": "ollama-cloud",
        "defaultModel": model_id,
        "enabledModels": [f"ollama-cloud/{model_id}"],
    }
    settings_path = pi_agent_dir / "settings.json"
    settings_path.write_text(json.dumps(settings_config, indent=2), encoding="utf-8")

    print(f"Wrote {models_path} (ollama-cloud provider registration)")
    print(f"Wrote {settings_path} pinning provider=ollama-cloud model={model_id}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
