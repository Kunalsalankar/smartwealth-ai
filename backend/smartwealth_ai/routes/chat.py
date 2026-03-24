from __future__ import annotations

from typing import Any

from flask import Blueprint, jsonify, request

from ..services.agent import run_agentic_chat
from ..services.gemini_client import load_gemini_config
from ..services.personalized_home import generate_personalized_home

chat_bp = Blueprint("chat", __name__)


@chat_bp.post("/chat")
def chat() -> Any:
    payload = request.get_json(silent=True) or {}
    message = payload.get("message", "")
    user_context = payload.get("user_context", {})

    if not isinstance(message, str) or not message.strip():
        return jsonify({"error": "message is required"}), 400

    if not isinstance(user_context, dict):
        return jsonify({"error": "user_context must be an object"}), 400

    result = run_agentic_chat(message=message, user_context=user_context)
    return jsonify(result)


@chat_bp.post("/personalized_home")
def personalized_home() -> Any:
    payload = request.get_json(silent=True) or {}
    user_type = payload.get("user_type", "")
    income = payload.get("income", "")
    goal = payload.get("goal", "")
    onboarding_preference = payload.get("onboarding_preference", "")

    if not isinstance(user_type, str) or not user_type.strip():
        return jsonify({"error": "user_type is required"}), 400
    if not isinstance(income, str) or not income.strip():
        return jsonify({"error": "income is required"}), 400
    if not isinstance(goal, str) or not goal.strip():
        return jsonify({"error": "goal is required"}), 400

    pref = onboarding_preference if isinstance(onboarding_preference, str) else ""

    result = generate_personalized_home(
        user_type=user_type.strip(),
        income=income.strip(),
        goal=goal.strip(),
        onboarding_preference=pref.strip(),
    )
    if result is None:
        cfg = load_gemini_config()
        if not cfg.api_keys:
            hint = "Add GEMINI_API_KEY (comma-separated for fallbacks) or GEMINI_API_KEYS in backend/.env."
        elif not cfg.models:
            hint = "Add GEMINI_MODEL or GEMINI_MODELS (e.g. gemini-2.0-flash) in backend/.env."
        else:
            hint = (
                "All API keys / models failed or the response was not valid JSON. "
                "Try GEMINI_MODELS=gemini-2.0-flash,gemini-1.5-flash "
                "and restart the server. Check terminal logs for details."
            )
        return jsonify({"error": f"Unable to generate personalized insights. {hint}"}), 503

    return jsonify(result)
