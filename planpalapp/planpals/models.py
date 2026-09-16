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

# Collaboration infrastructure models (ORM)
from planpals.collaboration.infrastructure.models import (  # noqa: F401
    AvailabilityPoll,
    AvailabilityOption,
    AvailabilityVote,
    PlanWorkItem,
    PlanComment,
    CommentMention,
    CommentReaction,
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

# Notification infrastructure models (ORM)
from planpals.notifications.infrastructure.models import (  # noqa: F401
    Notification,
    NotificationPreference,
    UserDeviceToken,
)

# Analytics infrastructure models (ORM)
from planpals.analytics.infrastructure.models import DailyMetric  # noqa: F401

# Budget infrastructure models (ORM)
from planpals.budgets.infrastructure.models import (  # noqa: F401
    Budget,
    Expense,
    ExpenseParticipant,
    ExpensePayment,
    RecurringExpense,
    Settlement,
)

# Sprint 5 experience models (ORM)
from planpals.experience.infrastructure.models import (  # noqa: F401
    GroupPoll,
    GroupPollOption,
    GroupPollVote,
    LiveLocationShare,
)

__all__ = [
    'BaseModel',
    'UserQuerySet', 'UserManager', 'User',
    'FriendshipQuerySet', 'FriendshipRejection', 'Friendship',
    'GroupQuerySet', 'Group', 'GroupMembershipQuerySet', 'GroupMembership',
    'PlanQuerySet', 'Plan', 'PlanActivity',
    'AvailabilityPoll', 'AvailabilityOption', 'AvailabilityVote',
    'PlanWorkItem', 'PlanComment', 'CommentMention', 'CommentReaction',
    'ConversationQuerySet', 'Conversation', 'ChatMessageQuerySet', 'ChatMessage', 'MessageReadStatus',
    'AuditLog',
    'Notification', 'NotificationPreference', 'UserDeviceToken',
    'DailyMetric',
    'Budget', 'Expense', 'ExpenseParticipant', 'ExpensePayment',
    'RecurringExpense', 'Settlement',
    'GroupPoll', 'GroupPollOption', 'GroupPollVote', 'LiveLocationShare',
]
