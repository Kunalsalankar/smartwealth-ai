from __future__ import annotations

from typing import Any

from .gemini_client import GeminiClient, load_gemini_config


def generate_personalized_home(
    user_type: str,
    income: str,
    goal: str,
    onboarding_preference: str = "",
) -> dict[str, Any] | None:
    """Return greeting + recommendations JSON from Gemini, or None if unavailable."""

    gemini = GeminiClient(load_gemini_config())
    if not gemini.enabled:
        return None

    pref_line = (
        f"\n- Onboarding preference: {onboarding_preference}"
        if onboarding_preference.strip()
        else ""
    )

    prompt = (
        "You are a financial advisor AI.\n\n"
        "User Profile:\n"
        f"* Type: {user_type}\n"
        f"* Monthly Income: {income}\n"
        f"* Goal: {goal}"
        f"{pref_line}\n\n"
        "Generate ONLY valid JSON with exactly these keys:\n"
        '"greeting" (string),\n'
        '"recommendations" (array of 2-3 strings),\n'
        '"next_action" (string),\n'
        '"tip" (string).\n\n'
        "Keep it simple, clear, and personalized. No markdown, no extra keys."
    )

    data = gemini.extract(prompt)
    if not isinstance(data, dict):
        return None

    greeting = str(data.get("greeting") or "").strip()
    recs_raw = data.get("recommendations")
    recommendations: list[str] = []
    if isinstance(recs_raw, list):
        recommendations = [
            str(x).strip() for x in recs_raw if str(x).strip()
        ][:3]
    next_action = str(data.get("next_action") or "").strip()
    tip = str(data.get("tip") or "").strip()

    if not greeting or len(recommendations) < 2 or not next_action or not tip:
        return None

    return {
        "greeting": greeting,
        "recommendations": recommendations,
        "next_action": next_action,
        "tip": tip,
    }
