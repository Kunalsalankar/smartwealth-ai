from __future__ import annotations

from typing import Any

from flask import Blueprint, jsonify, request

from ..services.agent import run_agentic_chat
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
        return jsonify(
            {
                "error": "Unable to generate personalized insights. "
                "Configure GEMINI_API_KEY and GEMINI_MODEL in backend .env."
            }
        ), 503

    return jsonify(result)
