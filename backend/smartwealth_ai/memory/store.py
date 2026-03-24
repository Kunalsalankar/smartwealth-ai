from __future__ import annotations

from typing import Any

# In-memory server-side memory store.
# Keyed by user_id; the mobile client should send back user_id in user_context.
USER_MEMORY: dict[str, dict[str, Any]] = {}
