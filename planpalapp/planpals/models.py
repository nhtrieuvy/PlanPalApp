"""
PlanPal Models - Facade Module

This file re-exports all models from their bounded context packages.
All existing imports (e.g., `from planpals.models import User`) continue to work.

Bounded contexts:
  - auth:    User, Friendship, FriendshipRejection
  - plans:   Plan, PlanActivity
  - groups:  Group, GroupMembership
  - chat:    Conversation, ChatMessage, MessageReadStatus
  - shared:  BaseModel
"""

# Shared
from planpals.shared.base_models import BaseModel  # noqa: F401

# Auth infrastructure models (ORM)
from planpals.auth.infrastructure.models import (  # noqa: F401
    UserQuerySet,
    UserManager,
    User,
    FriendshipQuerySet,
    FriendshipRejection,
    Friendship,
)

# Groups infrastructure models (ORM)
from planpals.groups.infrastructure.models import (  # noqa: F401
    GroupQuerySet,
    Group,
    GroupMembershipQuerySet,
    GroupMembership,
)

# Plans infrastructure models (ORM)
from planpals.plans.infrastructure.models import (  # noqa: F401
    PlanQuerySet,
    Plan,
    PlanActivity,
)

# Chat infrastructure models (ORM)
from planpals.chat.infrastructure.models import (  # noqa: F401
    ConversationQuerySet,
    Conversation,
    ChatMessageQuerySet,
    ChatMessage,
    MessageReadStatus,
)

# Audit infrastructure models (ORM)
from planpals.audit.infrastructure.models import AuditLog  # noqa: F401

__all__ = [
    'BaseModel',
    'UserQuerySet', 'UserManager', 'User',
    'FriendshipQuerySet', 'FriendshipRejection', 'Friendship',
    'GroupQuerySet', 'Group', 'GroupMembershipQuerySet', 'GroupMembership',
    'PlanQuerySet', 'Plan', 'PlanActivity',
    'ConversationQuerySet', 'Conversation', 'ChatMessageQuerySet', 'ChatMessage', 'MessageReadStatus',
    'AuditLog',
]
