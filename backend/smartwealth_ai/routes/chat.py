from __future__ import annotations

from typing import Any

from flask import Blueprint, jsonify, request

from ..services.agent import run_agentic_chat

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
