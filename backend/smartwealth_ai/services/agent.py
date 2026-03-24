from __future__ import annotations

import re
import uuid
from dataclasses import asdict, dataclass
from typing import Any

from ..memory.store import USER_MEMORY
from .gemini_client import GeminiClient, load_gemini_config


typedef_json = dict[str, Any]


@dataclass
class Profile:
    user_id: str
    user_type: str | None
    income: int | None
    income_range: str | None
    goal: str | None
    persona: str | None
    is_returning_user: bool


def run_agentic_chat(message: str, user_context: dict[str, Any]) -> dict[str, Any]:
    profile = profile_extractor(message=message, user_context=user_context)

    if user_context.get("flow") == "welcome":
        return run_welcome_concierge(message=message, profile=profile)

    need_data = need_identifier(message=message, profile=profile)
    recs = recommendation_engine(message=message, profile=profile, need_data=need_data)
    next_action = action_generator(profile=profile, need_data=need_data, recommendations=recs)

    assistant_message = assistant_responder(
        message=message,
        profile=profile,
        need_data=need_data,
        recommendations=recs,
        next_action=next_action,
    )

    return {
        "assistant_message": assistant_message,
        "profile": asdict(profile),
        "need": need_data["need"],
        "recommendations": recs,
        "next_action": next_action,
        "welcome": {"completed": True},
    }


def run_welcome_concierge(message: str, profile: Profile) -> dict[str, Any]:
    """3-turn welcome + profiling flow.

    The client should call /chat with user_context.flow=welcome.
    We store welcome progress in USER_MEMORY under the same user_id.
    """

    mem = USER_MEMORY.get(profile.user_id, {})
    welcome = mem.get("welcome") if isinstance(mem.get("welcome"), dict) else {}
    turn = int(welcome.get("turn", 0))
    completed = bool(welcome.get("completed", False))

    if completed:
        return {
            "assistant_message": "Welcome back — your onboarding path is ready. You can continue in chat.",
            "profile": asdict(profile),
            "need": "welcome_completed",
            "recommendations": [],
            "next_action": "Continue",
            "welcome": {"turn": turn, "completed": True, "products": welcome.get("products", []), "onboarding_path": welcome.get("onboarding_path", [])},
        }

    gemini = GeminiClient(load_gemini_config())

    if gemini.enabled:
        data = _welcome_with_gemini(gemini=gemini, message=message, profile=profile, turn=turn, memory=welcome)
        if isinstance(data, dict):
            # Persist
            USER_MEMORY[profile.user_id] = {
                **mem,
                "welcome": {
                    **welcome,
                    "turn": int(data.get("turn", turn)),
                    "completed": bool(data.get("completed", False)),
                    "products": data.get("products", welcome.get("products", [])),
                    "onboarding_path": data.get("onboarding_path", welcome.get("onboarding_path", [])),
                },
            }

            return {
                "assistant_message": str(data.get("assistant_message") or ""),
                "profile": asdict(profile),
                "need": "welcome_concierge",
                "recommendations": [],
                "next_action": str(data.get("next_action") or ""),
                "welcome": {
                    "turn": int(data.get("turn", turn)),
                    "completed": bool(data.get("completed", False)),
                    "products": data.get("products", []),
                    "onboarding_path": data.get("onboarding_path", []),
                },
            }

    # Fallback deterministic welcome (max 3 turns)
    if turn == 0:
        assistant_message = (
            "Welcome to ET! I’ll set up a quick 3-minute plan. "
            "To start: what’s your monthly income range and are you completely new to investing?"
        )
        next_action = "Share income range + investing experience"
        new_turn = 1
        products: list[dict[str, Any]] = []
        onboarding_path: list[dict[str, Any]] = []
        completed = False
    elif turn == 1:
        assistant_message = (
            "Thanks. Next: what’s your main goal right now — building savings, starting SIP, or learning basics?"
        )
        next_action = "Choose one goal"
        new_turn = 2
        products = []
        onboarding_path = []
        completed = False
    else:
        products = [
            {"product": "ET Money", "why": "Simple goal-based SIP journeys and tracking."},
            {"product": "ET Markets (Beginner SIP content)", "why": "Learn SIP basics in plain language."},
            {"product": "ET Masterclass", "why": "A guided session to start investing confidently."},
        ]
        onboarding_path = [
            {"step": 1, "title": "Learn SIP basics", "action": "Open ET Markets beginner content"},
            {"step": 2, "title": "Choose SIP amount", "action": "Start a small SIP plan"},
            {"step": 3, "title": "Track monthly", "action": "Use ET Money goal tracker"},
        ]
        assistant_message = (
            "Great — here’s a simple onboarding path. I’ll keep it jargon-free. "
            "I recommend ET Money + ET Markets beginner SIP content, and a short masterclass if you want guided help."
        )
        next_action = "Tap a product to start"
        new_turn = 3
        completed = True

    USER_MEMORY[profile.user_id] = {
        **mem,
        "welcome": {
            **welcome,
            "turn": new_turn,
            "completed": completed,
            "products": products,
            "onboarding_path": onboarding_path,
        },
    }

    return {
        "assistant_message": assistant_message,
        "profile": asdict(profile),
        "need": "welcome_concierge",
        "recommendations": [],
        "next_action": next_action,
        "welcome": {
            "turn": new_turn,
            "completed": completed,
            "products": products,
            "onboarding_path": onboarding_path,
        },
    }


def _welcome_with_gemini(
    gemini: GeminiClient,
    message: str,
    profile: Profile,
    turn: int,
    memory: dict[str, Any],
) -> dict[str, Any] | None:
    """Use Gemini to drive a <=3 turn welcome flow.

    Returns dict with:
    assistant_message (str), next_action (str), turn (int), completed (bool),
    products (list[{product, why}]), onboarding_path (list[{step,title,action}]).
    """

    prompt = (
        "You are ET Welcome Concierge. You greet new/returning users and in 3 turns or fewer "
        "collect minimal info (stage, experience, goal) and then recommend 2-3 ET products and a personalized onboarding path. "
        "Avoid jargon and overwhelming options. "
        "Return ONLY valid JSON with keys: assistant_message (string), next_action (string), "
        "turn (int), completed (bool), products (array of {product, why}), onboarding_path (array of {step,title,action}).\n\n"
        f"Current turn: {turn}. Completed so far: {bool(memory.get('completed', False))}.\n"
        f"Known profile: user_type={profile.user_type}, income={profile.income}, goal={profile.goal}, persona={profile.persona}.\n"
        f"User message: {message}"
    )

    extracted = gemini.extract(prompt)
    if not isinstance(extracted, dict):
        return None

    # Basic normalization
    extracted.setdefault("turn", min(turn + 1, 3))
    extracted.setdefault("completed", False)
    return extracted


def profile_extractor(message: str, user_context: dict[str, Any]) -> Profile:
    incoming_user_id = user_context.get("user_id")
    user_id = incoming_user_id if isinstance(incoming_user_id, str) and incoming_user_id else str(uuid.uuid4())

    is_returning_user = user_id in USER_MEMORY
    merged_context: dict[str, Any] = {}
    if is_returning_user:
        merged_context.update(USER_MEMORY[user_id])
    merged_context.update(user_context)

    msg = message.lower()

    # Deterministic extraction
    user_type = merged_context.get("user_type")
    if not user_type:
        if any(k in msg for k in ["student", "college", "university"]):
            user_type = "student"
        elif any(k in msg for k in ["salary", "salaried", "job", "employee"]):
            user_type = "salaried"
        elif any(k in msg for k in ["investor", "trader", "stocks", "mutual fund", "sip"]):
            user_type = "investor"

    income = merged_context.get("income")
    if not isinstance(income, int):
        income = _extract_income(msg)

    goal = merged_context.get("goal")
    if not goal:
        if any(k in msg for k in ["save", "saving", "emergency"]):
            goal = "saving"
        elif any(k in msg for k in ["invest", "investing", "sip", "mutual fund", "stocks"]):
            goal = "investing"
        elif any(k in msg for k in ["learn", "learning", "beginner", "guide"]):
            goal = "learning"

    persona = merged_context.get("persona")
    if not persona:
        if any(k in msg for k in ["beginner", "new to investing", "first time", "no experience"]):
            persona = "Beginner"
        elif any(k in msg for k in ["already investing", "investing for", "portfolio", "experienced"]):
            persona = "Experienced"

    # Gemini-assisted extraction (optional): fills missing values only
    gemini = GeminiClient(load_gemini_config())
    if gemini.enabled:
        data = gemini.extract(message)
        if isinstance(data, dict):
            if not user_type and data.get("user_type") in ["student", "salaried", "investor"]:
                user_type = data.get("user_type")
            if income is None and isinstance(data.get("income"), int):
                income = data.get("income")
            if not goal and data.get("goal") in ["saving", "investing", "learning"]:
                goal = data.get("goal")
            if not persona and data.get("persona") in ["Beginner", "Experienced"]:
                persona = data.get("persona")

    income_range = None
    if isinstance(income, int):
        if income < 30000:
            income_range = "<30000"
        elif income <= 50000:
            income_range = "30000-50000"
        else:
            income_range = ">50000"

    profile = Profile(
        user_id=user_id,
        user_type=user_type,
        income=income,
        income_range=income_range,
        goal=goal,
        persona=persona,
        is_returning_user=is_returning_user,
    )

    USER_MEMORY[user_id] = {
        "user_id": user_id,
        "user_type": profile.user_type,
        "income": profile.income,
        "goal": profile.goal,
        "persona": profile.persona,
    }

    return profile


def need_identifier(message: str, profile: Profile) -> dict[str, Any]:
    msg = message.lower()

    scenario = "returning_user" if profile.is_returning_user else "first_time_onboarding"

    if "home loan" in msg or "mortgage" in msg:
        scenario = "cross_sell_home_loan"

    # CTA / follow-up intents (so tapping buttons doesn't cause loops)
    if any(k in msg for k in ["open tools", "open tool", "open planning tools", "financial planning tools"]):
        return {"need": "use_planning_tools", "scenario": scenario}

    if any(k in msg for k in ["start sip", "start a sip", "sip", "begin sip"]):
        return {"need": "sip_onboarding", "scenario": scenario}

    if any(k in msg for k in ["explore et markets", "et markets", "beginner guide"]):
        return {"need": "explore_beginner_guide", "scenario": scenario}

    need = "general_financial_guidance"

    if profile.goal == "saving" or (profile.income is not None and profile.income < 30000):
        need = "build_saving_plan"
    elif profile.goal == "investing" or (profile.income is not None and profile.income > 50000):
        need = "start_sip_investment"
    elif profile.goal == "learning" or profile.persona == "Beginner":
        need = "learn_investing_basics"

    return {"need": need, "scenario": scenario}


def assistant_responder(
    message: str,
    profile: Profile,
    need_data: dict[str, Any],
    recommendations: list[dict[str, Any]],
    next_action: str,
) -> str:
    msg = message.strip()
    need = need_data.get("need")

    if need == "use_planning_tools":
        return (
            "Got it. I’ll guide you through the planning tools. "
            "First, tell me your monthly expenses and how much you can comfortably save each month."
        )

    if need == "sip_onboarding":
        income_hint = "" if profile.income is None else f" With income around ₹{profile.income}, "
        return (
            "Perfect — let’s start your SIP onboarding." + income_hint +
            "What’s your time horizon (1–3 yrs / 3–5 yrs / 5+ yrs) and risk comfort (low/medium/high)?"
        )

    if need == "explore_beginner_guide":
        return (
            "Great choice. Start with the beginner guide, then come back and tell me: "
            "do you prefer a safe balanced fund or a higher-growth option? I’ll suggest a first SIP."
        )

    # Default conversational response
    parts: list[str] = []

    if not profile.is_returning_user:
        parts.append("Thanks — I can help you build a simple, personalized plan.")
    else:
        parts.append("Welcome back — let’s continue from where we left off.")

    if profile.user_type:
        parts.append(f"You seem to be {profile.user_type}.")
    if profile.income_range:
        parts.append(f"Income range: {profile.income_range}.")
    if profile.goal:
        parts.append(f"Goal: {profile.goal}.")
    if profile.persona:
        parts.append(f"Persona: {profile.persona}.")

    if need == "build_saving_plan":
        parts.append("Priority: build an emergency fund and a consistent savings habit.")
    elif need == "start_sip_investment":
        parts.append("Priority: start investing consistently using SIP.")
    elif need == "learn_investing_basics":
        parts.append("Priority: learn the basics first, then start small and scale up.")
    elif need == "cross_sell_home_loan":
        parts.append("I also noticed home-loan intent — we can check EMI comfort and eligibility.")

    if recommendations:
        top = recommendations[0]
        title = str(top.get("title") or "")
        if title:
            parts.append(f"Top pick: {title}.")

    parts.append(next_action)
    return " ".join(parts)


def recommendation_engine(message: str, profile: Profile, need_data: dict[str, Any]) -> list[dict[str, Any]]:
    need = need_data["need"]
    scenario = need_data["scenario"]
    recs: list[dict[str, Any]] = []

    if profile.income is not None and profile.income < 30000:
        recs.append(
            {
                "type": "financial_planning_tools",
                "title": "Savings-first plan",
                "description": "Start with an emergency fund and a simple monthly savings plan.",
                "cta": "Build a saving plan",
            }
        )

    if profile.income is not None and profile.income > 50000:
        recs.append(
            {
                "type": "sip_investment",
                "title": "Start SIP (₹5,000+) ",
                "description": "Based on your income, a ₹5,000+ SIP can help you invest consistently.",
                "cta": "Start SIP",
                "amount": 5000,
            }
        )

    if need == "learn_investing_basics" or profile.persona == "Beginner":
        recs.append(
            {
                "type": "et_markets_guide",
                "title": "ET Markets beginner guide",
                "description": "A beginner-friendly guide to understand SIPs, mutual funds, and risk.",
                "cta": "Explore ET Markets",
            }
        )

    if need in ["build_saving_plan", "start_sip_investment", "general_financial_guidance"]:
        recs.append(
            {
                "type": "financial_planning_tools",
                "title": "Financial planning tools",
                "description": "Track spending, set goals, and see a personalized plan.",
                "cta": "Open tools",
            }
        )

    if scenario == "cross_sell_home_loan":
        recs.append(
            {
                "type": "home_loan_assist",
                "title": "Home loan readiness",
                "description": "Check eligibility, EMI comfort, and down-payment planning.",
                "cta": "Check home loan readiness",
            }
        )

    seen: set[tuple[str, str]] = set()
    deduped: list[dict[str, Any]] = []
    for r in recs:
        k = (str(r.get("type")), str(r.get("title")))
        if k not in seen:
            seen.add(k)
            deduped.append(r)

    return deduped


def action_generator(profile: Profile, need_data: dict[str, Any], recommendations: list[dict[str, Any]]) -> str:
    scenario = need_data["scenario"]
    need = need_data["need"]

    if scenario == "first_time_onboarding":
        if need == "build_saving_plan":
            return "Answer 2 questions to generate your saving plan."
        if need == "start_sip_investment":
            return "Pick your SIP amount and risk level to begin onboarding."
        if need == "learn_investing_basics":
            return "Start the 5-minute beginner flow and we’ll recommend a first SIP."

    if scenario == "cross_sell_home_loan":
        return "Share your expected home price and down-payment to evaluate EMI comfort."

    if recommendations:
        return f"Choose an option to proceed: {recommendations[0].get('cta', 'Continue')}"

    return "Tell me your monthly income and your goal (saving/investing/learning)."


def _extract_income(msg: str) -> int | None:
    m = re.search(r"(earn|income|salary)\s*(is|:)?\s*₹?\s*([0-9]{2,3}(?:,[0-9]{3})*|[0-9]+)\s*(k|K)?", msg)
    if not m:
        m = re.search(r"₹\s*([0-9]{2,3}(?:,[0-9]{3})*|[0-9]+)\s*(k|K)?", msg)

    if not m:
        return None

    raw_num = m.group(3) if m.lastindex and m.lastindex >= 3 else None
    if not raw_num:
        return None

    num = int(raw_num.replace(",", ""))
    suffix = m.group(4) if m.lastindex and m.lastindex >= 4 else None
    if suffix in ["k", "K"]:
        num *= 1000

    if num <= 0:
        return None

    return num
