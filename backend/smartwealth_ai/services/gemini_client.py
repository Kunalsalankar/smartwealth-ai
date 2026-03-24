from __future__ import annotations

import json
import logging
import os
import re
from dataclasses import dataclass
from typing import Any

from dotenv import load_dotenv

logger = logging.getLogger(__name__)


@dataclass
class GeminiConfig:
    api_keys: list[str]
    models: list[str]


def _split_csv(value: str | None) -> list[str]:
    if not value:
        return []
    # Split on comma; trim whitespace; drop empties (supports multiple keys/models).
    return [v.strip() for v in value.split(",") if v.strip()]


def _collect_api_keys() -> list[str]:
    """Merge keys from GEMINI_API_KEY, GEMINI_API_KEYS (comma-separated), and newlines."""
    raw_main = os.getenv("GEMINI_API_KEY") or ""
    raw_extra = os.getenv("GEMINI_API_KEYS") or ""

    keys: list[str] = []
    for chunk in (raw_main, raw_extra):
        chunk = chunk.strip()
        if not chunk:
            continue
        # Allow newline-separated lists as well as comma-separated
        for part in re.split(r"[\s,]+", chunk):
            p = part.strip()
            if p:
                keys.append(p)
    # Deduplicate while preserving order
    seen: set[str] = set()
    out: list[str] = []
    for k in keys:
        if k not in seen:
            seen.add(k)
            out.append(k)
    return out


def _normalize_model_name(name: str) -> list[str]:
    """Return candidates to try with GenerativeModel (SDK accepts short or long form)."""
    n = name.strip()
    if not n:
        return []
    variants: list[str] = []
    if n.startswith("models/"):
        variants.append(n)
        variants.append(n.removeprefix("models/"))
    else:
        variants.append(n)
        variants.append(f"models/{n}")
    # Deduplicate
    seen: set[str] = set()
    ordered: list[str] = []
    for v in variants:
        if v and v not in seen:
            seen.add(v)
            ordered.append(v)
    return ordered


def load_gemini_config() -> GeminiConfig:
    load_dotenv(override=False)

    keys = _collect_api_keys()
    models = _split_csv(os.getenv("GEMINI_MODELS"))

    single_model = os.getenv("GEMINI_MODEL")
    if single_model and single_model.strip():
        models = [single_model.strip()]

    return GeminiConfig(api_keys=keys, models=models)


def _response_text(resp: Any) -> str | None:
    """Best-effort plain text from a generate_content response."""
    try:
        t = getattr(resp, "text", None)
        if isinstance(t, str) and t.strip():
            return t.strip()
    except Exception:
        pass

    try:
        parts: list[str] = []
        for c in getattr(resp, "candidates", None) or []:
            content = getattr(c, "content", None)
            if content is None:
                continue
            for p in getattr(content, "parts", None) or []:
                pt = getattr(p, "text", None)
                if isinstance(pt, str) and pt:
                    parts.append(pt)
        if parts:
            return "".join(parts).strip()
    except Exception:
        pass

    return None


def _parse_json_object(text: str) -> dict[str, Any] | None:
    """Parse a single JSON object from model output (handles markdown fences and extra prose)."""
    raw = text.strip()

    if "```" in raw:
        m = re.search(r"```(?:json)?\s*([\s\S]*?)\s*```", raw, re.IGNORECASE)
        if m:
            raw = m.group(1).strip()

    try:
        data = json.loads(raw)
        return data if isinstance(data, dict) else None
    except json.JSONDecodeError:
        pass

    start = raw.find("{")
    end = raw.rfind("}")
    if start != -1 and end != -1 and end > start:
        try:
            data = json.loads(raw[start : end + 1])
            return data if isinstance(data, dict) else None
        except json.JSONDecodeError:
            pass

    return None


class GeminiClient:
    def __init__(self, config: GeminiConfig):
        self._config = config

    @property
    def enabled(self) -> bool:
        return bool(self._config.api_keys) and bool(self._config.models)

    def extract(self, prompt: str) -> dict[str, Any] | None:
        """Best-effort JSON object extraction using Gemini."""
        if not self.enabled:
            logger.warning("Gemini disabled: missing API keys or models in .env")
            return None

        import google.generativeai as genai  # type: ignore

        models_to_try: list[str] = []
        seen_m: set[str] = set()
        for m in self._config.models:
            for v in _normalize_model_name(m):
                if v not in seen_m:
                    seen_m.add(v)
                    models_to_try.append(v)

        last_error: str | None = None
        for api_key in self._config.api_keys:
            try:
                genai.configure(api_key=api_key)
            except Exception as e:  # noqa: BLE001
                last_error = str(e)
                logger.exception("genai.configure failed for one key: %s", e)
                continue

            for model_name in models_to_try:
                try:
                    model = genai.GenerativeModel(model_name)
                    resp = model.generate_content(prompt)
                    text = _response_text(resp)
                    if not text:
                        last_error = f"Empty response (model={model_name})"
                        continue

                    data = _parse_json_object(text)
                    if isinstance(data, dict):
                        return data
                    last_error = f"Could not parse JSON (model={model_name})"
                except Exception as e:  # noqa: BLE001
                    last_error = str(e)
                    logger.debug("Gemini attempt failed key=… model=%s: %s", model_name, e)
                    continue

        if last_error:
            logger.warning("All Gemini attempts failed: %s", last_error)
        return None
