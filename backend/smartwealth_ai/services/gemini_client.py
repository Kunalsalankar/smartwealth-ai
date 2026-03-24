from __future__ import annotations

import json
import os
from dataclasses import dataclass
from typing import Any

from dotenv import load_dotenv


@dataclass
class GeminiConfig:
    api_keys: list[str]
    models: list[str]


def _split_csv(value: str | None) -> list[str]:
    if not value:
        return []
    return [v.strip() for v in value.split(",") if v.strip()]


def load_gemini_config() -> GeminiConfig:
    # Loads from backend/.env or repo-root .env if present.
    load_dotenv(override=False)

    keys = _split_csv(os.getenv("GEMINI_API_KEY"))
    models = _split_csv(os.getenv("GEMINI_MODELS"))

    single_model = os.getenv("GEMINI_MODEL")
    if single_model and single_model.strip():
        models = [single_model.strip()]

    return GeminiConfig(api_keys=keys, models=models)


class GeminiClient:
    def __init__(self, config: GeminiConfig):
        self._config = config

    @property
    def enabled(self) -> bool:
        return bool(self._config.api_keys) and bool(self._config.models)

    def extract(self, prompt: str) -> dict[str, Any] | None:
        """Best-effort JSON extraction using Gemini. Returns None if unavailable."""
        if not self.enabled:
            return None

        # Import lazily so the app still runs without the dependency.
        import google.generativeai as genai  # type: ignore

        for api_key in self._config.api_keys:
            try:
                genai.configure(api_key=api_key)
                model = genai.GenerativeModel(self._config.models[0])
                resp = model.generate_content(prompt)

                text = getattr(resp, "text", None)
                if not isinstance(text, str) or not text.strip():
                    continue

                cleaned = text.strip()
                if cleaned.startswith("```"):
                    cleaned = cleaned.strip("`")
                    cleaned = cleaned.replace("json", "", 1).strip()

                data = json.loads(cleaned)
                if isinstance(data, dict):
                    return data
            except Exception:
                continue

        return None
