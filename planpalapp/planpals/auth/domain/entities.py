"""
Auth Domain — Pure Python Entities, Value Objects & Constants

This file is the innermost layer of Clean Architecture.
NO Django imports, NO ORM, NO REST framework — Pure Python only.

All bounded contexts and external layers may depend on these definitions,
but this file must NEVER import from application, infrastructure, or presentation.
"""
from enum import Enum
from dataclasses import dataclass
from typing import Optional
from datetime import datetime, timedelta


# ============================================================================
# Enums / Constants
# ============================================================================

class FriendshipStatus(str, Enum):
    PENDING = 'pending'
    ACCEPTED = 'accepted'
    REJECTED = 'rejected'
    BLOCKED = 'blocked'


# Rejection cooldown rules
REJECTION_COOLDOWN_HOURS = 24
MAX_REJECTION_COUNT = 3
EXTENDED_COOLDOWN_DAYS = 7


# ============================================================================
# Pure domain functions
# ============================================================================

def can_resend_after_rejection(
    rejection_count: int,
    last_rejection_time: Optional[datetime],
    now: datetime,
) -> tuple[bool, str]:
    """
    Check if a friend request can be resent after rejection.
    Returns (can_resend, reason_message).
    """
    if last_rejection_time is None:
        return True, ""

    elapsed = now - last_rejection_time

    if rejection_count >= MAX_REJECTION_COUNT:
        cooldown = timedelta(days=EXTENDED_COOLDOWN_DAYS)
        msg = f"Must wait {EXTENDED_COOLDOWN_DAYS} days after {rejection_count} rejections"
    else:
        cooldown = timedelta(hours=REJECTION_COOLDOWN_HOURS)
        msg = f"Must wait {REJECTION_COOLDOWN_HOURS} hours after rejection"

    if elapsed < cooldown:
        remaining = cooldown - elapsed
        return False, f"Cannot resend friend request yet. {msg}. Time remaining: {remaining}"

    return True, ""
