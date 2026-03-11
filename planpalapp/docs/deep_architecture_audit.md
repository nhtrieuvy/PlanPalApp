# PlanPal Deep Architecture Audit

**Date:** 2025-01-XX  
**Auditor:** Principal Backend Engineer Review  
**Stack:** Django 5.2.6 · DRF 3.14.0 · MySQL · Redis · Celery 5.3.1 · Django Channels · OAuth2  
**Codebase:** ~70 files, 6 bounded contexts, 4 architectural layers

---

## Table of Contents

1. [Clean Architecture Compliance](#1-clean-architecture-compliance)
2. [Dependency Rule Enforcement](#2-dependency-rule-enforcement)
3. [Bounded Context Correctness](#3-bounded-context-correctness)
4. [Domain Logic Placement](#4-domain-logic-placement)
5. [Command Handler Correctness](#5-command-handler-correctness)
6. [Database Performance](#6-database-performance)
7. [Redis Cache Architecture](#7-redis-cache-architecture)
8. [Celery Async Architecture](#8-celery-async-architecture)
9. [RBAC Permission System](#9-rbac-permission-system)
10. [OAuth2 Security](#10-oauth2-security)
11. [Dead Code Detection](#11-dead-code-detection)
12. [Dead File Detection](#12-dead-file-detection)
13. [Scalability Analysis](#13-scalability-analysis)
14. [Final Optimized Architecture](#14-final-optimized-architecture)

---

## 1. Clean Architecture Compliance

**Score: 6.5/10**

### Layer Structure

Each bounded context follows a 4-layer structure:

```
context/
├── domain/          # Entities, value objects, repository ABCs, domain events
├── application/     # Services, commands, handlers, factories
├── infrastructure/  # ORM models, Django repos, Celery tasks, consumers
├── presentation/    # DRF views, serializers, permissions
```

This layout is correct. The separation exists and is consistently applied across plans, groups, auth, and chat.

### What Works

- **Domain layer purity:** `domain/entities.py` files contain only pure Python — enums, dataclasses, validation functions. Zero Django imports.
- **Domain events are pure:** `PlanCreated`, `GroupMemberAdded`, `FriendRequestSent` etc. are frozen dataclasses inheriting from `DomainEvent`.
- **Repository ABCs in domain:** `PlanRepository`, `GroupRepository`, `UserRepository` etc. are abstract base classes that return `Any` — no Django dependency.
- **Command pattern:** Frozen dataclass commands like `CreatePlanCommand(title, description, ...)` are pure value objects.
- **Handler DI:** Handlers accept repository interfaces via constructor injection:
  ```python
  class CreatePlanHandler(BaseCommandHandler[CreatePlanCommand, Any]):
      def __init__(self, plan_repo: PlanRepository, event_publisher: DomainEventPublisher):
  ```

### Critical Violations

#### V1. Service Layer Bypasses Handler Pattern

`PlanService.add_activity_with_place()` bypasses `AddActivityHandler` entirely, calling `activity_repo.save_new_from_dict()` directly:

```python
# plans/application/services.py
@classmethod
def add_activity_with_place(cls, plan, title, start_time, end_time, place_id=None, **kwargs):
    activity_repo = get_activity_repo()
    # ... builds dict manually ...
    activity = activity_repo.save_new_from_dict(activity_data)  # BYPASSES HANDLER
```

**Fix:** Route through `AddActivityHandler` and enrich with Goong place data before command dispatch.

#### V2. `ConversationService.create_message()` Bypasses `SendMessageHandler`

`SendMessageHandler` exists in `chat/application/handlers.py` but is **never called**. All message creation goes through `ConversationService.create_message()` which directly creates ORM objects:

```python
# chat/application/services.py
@classmethod
def create_message(cls, conversation, sender, validated_data):
    message = ChatMessage.objects.create(...)  # DIRECT ORM, no handler
```

#### V3. `GroupCreateSerializer.create()` Bypasses `AddMemberHandler`

The serializer's `create()` method calls `GroupService.add_member()` in a loop but the service itself orchestrates via `AddMemberHandler`. However, the serializer imports `GroupService` — a presentation→application dependency — and orchestrates member addition logic that belongs in the application layer:

```python
# groups/presentation/serializers.py
def create(self, validated_data):
    ...
    for user_id in initial_members:
        GroupService.add_member(group, user, role='member')
```

#### V4. `DjangoUserRepository.update_profile()` Imports DRF Serializer

```python
# auth/infrastructure/repositories.py
from planpals.auth.presentation.serializers import UserSerializer
```

Infrastructure importing from presentation layer — a direct dependency rule violation.

#### V5. `ChatMessage.save()` Contains Service-Level Side Effects

```python
# chat/infrastructure/models.py
def save(self, *args, **kwargs):
    super().save(*args, **kwargs)
    if self.conversation:
        self.conversation.last_message_at = self.updated_at
        self.conversation.save(update_fields=['last_message_at'])
        # clears unread cache for ALL participants
```

Domain model triggers cache invalidation and cross-model updates — this belongs in a handler or service.

---

## 2. Dependency Rule Enforcement

**Score: 6.0/10**

### Correct Dependencies (Inner → Outer: Domain → Application → Infrastructure → Presentation)

| From | To | Status |
|------|----|--------|
| domain/ | (no imports) | ✅ Pure |
| application/handlers.py | domain/, shared.interfaces | ✅ Clean |
| application/commands.py | (stdlib only) | ✅ Pure |
| infrastructure/models.py | domain/entities (enums) | ✅ Acceptable |
| infrastructure/repositories.py | domain/repositories (ABCs) | ✅ Correct |
| presentation/views.py | application/services | ✅ Correct |

### Violations

#### D1. Infrastructure → Presentation (CRITICAL)

```python
# auth/infrastructure/repositories.py
from planpals.auth.presentation.serializers import UserSerializer
```

`DjangoUserRepository.update_profile()` uses a DRF serializer for validation in the infrastructure layer.

**Fix:** Move validation to the application layer handler. The repository should only persist data.

```python
# auth/application/handlers.py — PROPOSED
class UpdateProfileHandler(BaseCommandHandler):
    def handle(self, command: UpdateProfileCommand):
        # Validate in application layer
        validated = self._validate_profile_data(command.data)
        self.user_repo.update_fields(command.user_id, **validated)
```

#### D2. Application Layer Cross-Context Direct Import

```python
# auth/application/services.py
from planpals.groups.application.services import GroupService

class UserService:
    @classmethod
    def join_group(cls, user, group_id, invite_code=None):
        return GroupService.join_group(...)
```

This creates a hard coupling between auth and groups application layers. Should use an interface or route through the presentation layer.

#### D3. Factory Files Import Concrete Infrastructure

```python
# groups/application/factories.py
from planpals.auth.infrastructure.repositories import DjangoFriendshipRepository
from planpals.chat.infrastructure.repositories import DjangoConversationRepository
```

Factory files break bounded context isolation by importing infrastructure from other contexts. This is semi-acceptable as factories are "composition root" components, but ideally cross-context wiring should be centralized.

#### D4. Shared Tasks Import Model Facade

```python
# shared/tasks.py
from planpals.models import Plan, Group, User
```

The facade (`planpals/models.py`) re-exports all models. Tasks importing via the facade is acceptable but creates tight coupling to specific ORM models in what should be a shared concern.

#### D5. Presentation Serializer Imports Across Contexts

```python
# groups/presentation/serializers.py
from planpals.auth.presentation.serializers import UserSummarySerializer
from planpals.models import User, Friendship  # Cross-context model import

# plans/presentation/serializers.py
from planpals.auth.presentation.serializers import UserSummarySerializer
from planpals.groups.presentation.serializers import GroupSummarySerializer
from planpals.models import Group, GroupMembership
```

Presentation layer cross-context imports are somewhat inevitable in a monolith, but they create a tight coupling web that makes context extraction difficult.

### Dependency Graph Summary

```
auth.presentation ← plans.presentation (UserSummarySerializer)
auth.presentation ← groups.presentation (UserSummarySerializer)  
auth.presentation ← chat.presentation (UserSummarySerializer)
groups.presentation ← plans.presentation (GroupSummarySerializer)
groups.presentation ← chat.presentation (GroupSummarySerializer)

auth.infrastructure ← groups.application.factories (DjangoFriendshipRepo)
chat.infrastructure ← groups.application.factories (DjangoConversationRepo)
groups.application ← auth.application (GroupService← UserService.join_group)
```

---

## 3. Bounded Context Correctness

**Score: 7.0/10**

### Context Map

| Context | Models | Commands | Handlers | Has domain/ | Has events |
|---------|--------|----------|----------|-------------|------------|
| plans | Plan, PlanActivity | 9 | 9 | ✅ | ✅ (8 events) |
| groups | Group, GroupMembership | 8 | 7 | ✅ | ✅ (3 events) |
| auth | User, Friendship, FriendshipRejection | 9 | 9 | ✅ | ✅ (4 events) |
| chat | Conversation, ChatMessage, MessageReadStatus | 7 | 5 | ✅ | ❌ no events |
| notifications | (no models) | 0 | 0 | ❌ thin | ❌ |
| locations | (no models) | 0 | 0 | ❌ thin | ❌ |

### Issues

#### BC1. Chat Context Has No Domain Events

All other major contexts publish domain events, but chat mutations (`create_message`, `edit_message`, `delete_message`) produce no `DomainEvent` subclasses. Instead, `ConversationService` directly calls `RealtimeEventPublisher.publish_new_message()`:

```python
# chat/application/services.py
publisher.publish_new_message(conversation_id=..., message_data=...)
```

This bypasses the domain event pipeline (`ChannelsDomainEventPublisher` → `_event_registry` → infrastructure handlers) and hard-couples chat to the realtime publisher.

**Fix:** Create `chat/domain/events.py` with `MessageCreated`, `MessageEdited`, `MessageDeleted` events. Have handlers publish these.

#### BC2. Auth Context Owns a `GroupRepository` Interface

```python
# auth/domain/repositories.py
class GroupRepository(ABC):
    @abstractmethod
    def get_user_groups(self, user_id) -> Any: ...
    @abstractmethod
    def get_group_by_id(self, group_id) -> Any: ...
    @abstractmethod
    def is_group_member(self, group_id, user_id) -> bool: ...
```

This is a cross-context query interface — auth defines what it needs from groups. The implementation (`DjangoAuthGroupRepository`) imports `Group` model directly. This pattern is acceptable as an Anti-Corruption Layer but should be named more explicitly (e.g., `GroupQueryPort`).

#### BC3. Chat Context Has Cross-Context Query Repositories

```python
# chat/domain/repositories.py
class FriendshipQueryRepository(ABC): ...
class GroupQueryRepository(ABC): ...
```

Good pattern — chat declares the queries it needs from other contexts as ABCs. However, these are defined but appear to not be fully used (chat services import models directly instead).

#### BC4. `UpdateGroupCommand` Has No Handler

```python
# groups/application/commands.py
@dataclass(frozen=True)
class UpdateGroupCommand(BaseCommand):
    group_id: str
    name: Optional[str] = None
    description: Optional[str] = None
```

This command exists but no `UpdateGroupHandler` exists. Group updates go through DRF's `UpdateModelMixin` → `serializer.update()` directly, bypassing the command/handler pattern.

---

## 4. Domain Logic Placement

**Score: 6.0/10**

### Correct Placements

- **`plans/domain/entities.py`:** `validate_activity_times()`, `validate_coordinates()`, `validate_estimated_cost()`, `validate_plan_dates()` — pure validation functions reused by both serializers and handlers.
- **`auth/domain/entities.py`:** `can_resend_after_rejection()` with `REJECTION_COOLDOWN_HOURS` — pure business rule.
- **`plans/domain/entities.py`:** `PlanStatus` enum with valid transitions implicitly defined. `ChangePlanStatusHandler` has `VALID_TRANSITIONS` dict.

### Violations

#### DL1. Business Logic in ORM Models

**`Plan` model** contains status transition logic, collaborator resolution, and schedule computation:

```python
# plans/infrastructure/models.py
class Plan(BaseModel):
    @property
    def collaborators(self):
        if self.is_group_plan() and self.group:
            return list(self.group.members.all())
        return [self.creator]

    @property
    def activities_by_date(self):
        # Groups activities by date — business logic in infrastructure
```

**`Conversation` model** contains participant resolution, display name generation, and unread count computation:

```python
# chat/infrastructure/models.py  
class Conversation(BaseModel):
    @property
    def display_name(self):
        # Business logic for conversation naming

    def get_unread_count(self, user):
        # Query + business logic in model
```

**`Group` model** contains member permission checks:

```python
# groups/infrastructure/models.py
class Group(BaseModel):
    def is_admin(self, user):
        return self.memberships.filter(user=user, role=GroupMembership.ADMIN).exists()
    
    def is_member(self, user):
        return self.members.filter(id=user.id).exists()
```

**`ChatMessage.save()`** triggers side effects (updating conversation timestamp, clearing unread caches).

**Fix pattern:** Move business logic to domain entities or application services. Models should only be persistence representations.

#### DL2. `PlanActivity.duration_hours` Naming Bug

```python
# plans/infrastructure/models.py
@property
def duration_hours(self):
    if self.start_time and self.end_time:
        delta = self.end_time - self.start_time
        return delta.total_seconds() / 3600  # Returns HOURS, not minutes
    return 0
```

The property name says "hours" and correctly returns hours. However, the serializer then treats values `< 1` as minutes:

```python
# plans/presentation/serializers.py
def get_duration_display(self, instance):
    hours = instance.duration_hours
    if hours < 1:
        minutes = int(hours * 60)  # Converts fractional hours to minutes
```

This is actually correct behavior — `0.5` hours → `30` minutes. The property name is accurate. **No bug here** — earlier assessment was incorrect.

#### DL3. Status Transition Logic Split Across Layers

`ChangePlanStatusHandler` defines `VALID_TRANSITIONS` as a handler-level dict:

```python
# plans/application/handlers.py
VALID_TRANSITIONS = {
    'upcoming': ['ongoing', 'cancelled'],
    'ongoing': ['completed', 'cancelled'],
}
```

This is domain invariant logic that should live in `plans/domain/entities.py` alongside the `PlanStatus` enum.

#### DL4. Validation Duplication

Validation is performed in both serializers and handlers. For example, date validation:
- `PlanCreateSerializer.validate()` calls `validate_plan_dates()`
- `CreatePlanHandler.handle()` also validates dates

This double validation is defensive but indicates unclear ownership. Domain validation should be canonical in the domain layer; serializers should only do format validation (e.g., "is this a valid UUID?").

---

## 5. Command Handler Correctness

**Score: 6.5/10**

### Handler Inventory

| Context | Handlers | All use DI? | All publish events? | All use UoW? |
|---------|----------|------------|---------------------|--------------|
| plans | 9 | ✅ | ✅ (8/9) | ❌ 0/9 |
| groups | 7 | ✅ | ✅ (7/7) | ❌ 0/7 |
| auth | 9 | ✅ | ✅ (6/9) | ❌ 0/9 |
| chat | 5 | ✅ | ❌ (0/5) | ❌ 0/5 |

### Critical Issues

#### CH1. `DjangoUnitOfWork` Defined but NEVER Used

```python
# shared/infrastructure.py
class DjangoUnitOfWork:
    def __enter__(self):
        self._atomic = transaction.atomic()
        self._atomic.__enter__()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self._atomic.__exit__(exc_type, exc_val, exc_tb)
    
    def commit(self): pass
    def rollback(self): transaction.set_rollback(True)
```

**Zero handlers use this.** All mutations rely on Django's autocommit mode. This means multi-step operations (e.g., `CreateGroupHandler` which creates a group + adds admin membership + creates conversation + publishes events) are **not atomic**.

**Risk:** If `CreateGroupHandler` creates the group but fails during membership creation, you get an orphaned group with no admin.

**Fix:** All mutating handlers should use `@transaction.atomic` or the `UnitOfWork`:

```python
class CreateGroupHandler(BaseCommandHandler):
    def handle(self, command):
        with DjangoUnitOfWork() as uow:
            group = self.group_repo.create(...)
            self.membership_repo.add_admin(...)
            self.event_publisher.publish(GroupCreated(...))
```

#### CH2. `JoinPlanHandler` Missing Event Publisher

```python
# plans/application/handlers.py
class JoinPlanHandler(BaseCommandHandler):
    def __init__(self, plan_repo: PlanRepository):
        self.plan_repo = plan_repo
    # NO event_publisher — user joining a plan emits no domain event
```

Compare with `JoinGroupHandler` which correctly publishes `GroupMemberAdded`. Plan join should emit a similar event for real-time notifications.

#### CH3. Auth Commands Don't Extend `BaseCommand`

```python
# auth/application/commands.py
@dataclass(frozen=True)
class SendFriendRequestCommand:  # No BaseCommand inheritance
    user_id: UUID
    target_user_id: UUID
```

While `BaseCommand` has minimal functionality (just `timestamp` and `command_id`), inconsistency breaks the contract. All commands should inherit from `BaseCommand` for traceability.

#### CH4. Chat Handlers Are Mostly Dead

| Handler | Used? | Called By |
|---------|-------|-----------|
| `SendMessageHandler` | ❌ DEAD | Nobody — `ConversationService.create_message()` is used instead |
| `CreateSystemMessageHandler` | ✅ | `ConversationService.create_system_message()` |
| `EditMessageHandler` | ✅ | `ChatService.edit_message()` |
| `DeleteMessageHandler` | ✅ | `ChatService.delete_message()` |
| `MarkMessagesReadHandler` | ✅ | `ConversationService.mark_messages_read()` |

#### CH5. Service-Handler Impedance Mismatch

Services use `@classmethod` and static factory methods. Handlers use constructor-injected DI. This creates two competing patterns:

```python
# Pattern 1: Service (classmethod, static factory)
PlanService.create_plan(creator, title, ...)  # calls get_create_plan_handler() internally

# Pattern 2: Handler (DI via factory)
handler = get_create_plan_handler()
handler.handle(CreatePlanCommand(...))
```

Views call services, which internally create handlers via factories. This indirection adds complexity without benefit — views could call handlers directly via factories.

---

## 6. Database Performance

**Score: 7.5/10**

### What Works

- **Custom QuerySets** with annotated stats: `PlanQuerySet.with_stats()`, `GroupQuerySet.with_full_stats()`, `UserQuerySet.with_counts()` — these use `annotate()` with `Count`, `Sum`, etc. to avoid N+1 queries.
- **Composite indexes** on frequently queried columns.
- **`select_related` and `prefetch_related`** used consistently in ViewSet `get_queryset()` methods.
- **`PlanQuerySet.with_stats()`** annotates `activities_count`, `total_estimated_cost`, `duration_days` in a single query.
- **Optimistic locking** on `PlanActivity` via `version` field with CAS in `update_status_atomic()`.

### Issues

#### DB1. N+1 in `PlanSerializer.get_collaborators()`

```python
# plans/presentation/serializers.py
def get_collaborators(self, obj):
    collaborators = obj.collaborators  # Property hits DB if group not prefetched
    return UserSummarySerializer(collaborators, many=True, ...).data
```

`Plan.collaborators` calls `self.group.members.all()` — if group members aren't prefetched, this generates N+1 queries when serializing a list of plans.

**Mitigation:** The ViewSet does `prefetch_related('group__members')` for `retrieve` action but NOT for `list`. For list views using `PlanSummarySerializer` (which doesn't include collaborators), this is fine. But `PlanSerializer` used in `join` action response doesn't get the prefetch.

#### DB2. `ChatMessage.save()` Triggers Extra Queries

Every message save triggers:
1. `self.conversation.save(update_fields=['last_message_at'])` — 1 extra UPDATE
2. Cache clearing for all participants — potentially N cache delete calls

This should be moved to the service layer where batching and deferral are possible.

#### DB3. `User.friends` Property Bug

```python
# auth/infrastructure/models.py
@property
def friends(self):
    return self.objects.friends_of(self)  # BUG: self.objects doesn't work
```

`self.objects` is invalid — `objects` is a class-level manager, not instance-level. Should be `User.objects.friends_of(self)` or `self.__class__.objects.friends_of(self)`.

#### DB4. Conversation.get_unread_count() Performs Full Query

```python
# chat/infrastructure/models.py
def get_unread_count(self, user):
    return self.messages.filter(...).exclude(sender=user).exclude(
        read_statuses__user=user
    ).count()
```

This executes a COUNT query every time. For conversation list views showing 20 conversations, that's 20 extra queries. Should be annotated in the queryset or cached.

#### DB5. Missing Index on `ChatMessage.conversation_id + created_at`

Chat message pagination uses `ordering = '-created_at'` with cursor pagination filtered by `conversation_id`. A composite index `(conversation_id, created_at DESC)` would significantly improve pagination performance for conversations with many messages.

#### DB6. `FriendRequestListView.get_queryset()` Doesn't Annotate

The queryset uses `select_related('user_a', 'user_b', 'initiator')` but the serializer's `get_user()` and `get_friend()` methods may trigger additional queries for `UserSummarySerializer` fields like `avatar_url`.

---

## 7. Redis Cache Architecture

**Score: 7.5/10**

### Architecture

```
CachePort (ABC)  ←  DjangoCacheService (stampede prevention)
                 ←  NullCacheService (tests)
                 
CacheKeys.plan_summary(plan_id)     → "planpal:v1:plan_summary:{id}"
CacheKeys.user_profile(user_id)     → "planpal:v1:user_profile:{id}"
CacheKeys.group_detail(group_id)    → "planpal:v1:group_detail:{id}"

CacheTTL.USER_PROFILE  = 120s
CacheTTL.PLAN_SUMMARY  = 180s
CacheTTL.GROUP_DETAIL   = 180s
```

### What Works

- **Stampede prevention** via lock-based `get_or_set()`:
  ```python
  lock_key = f"{key}:lock"
  if cache.add(lock_key, "1", timeout=lock_timeout):
      try:
          value = callback()
          cache.set(key, value, timeout=ttl)
      finally:
          cache.delete(lock_key)
  ```
- **Version-prefixed keys** (`planpal:v1:`) enabling bulk invalidation on schema changes.
- **`NullCacheService`** for tests — no Redis dependency in test suite.
- **Cache invalidation** in service layer: `_invalidate_plan_cache()`, `_invalidate_group_cache()`.

### Issues

#### CA1. Inconsistent Cache Usage

Only 3 entities are cached: plan summary, user profile, group detail. Chat conversations, activity lists, and friendship data are not cached despite being frequently accessed.

#### CA2. Cache Invalidation Race Condition

```python
# plans/application/services.py
@classmethod
def _invalidate_plan_cache(cls, plan_id):
    cache_service = get_cache_service()
    cache_service.delete(CacheKeys.plan_summary(plan_id))
```

Between cache deletion and next read, multiple requests can hit the DB simultaneously (thundering herd). The stampede prevention in `get_or_set()` helps, but `delete()` + subsequent `get_or_set()` still has a window.

**Fix:** Use cache-aside with TTL refresh instead of delete-then-recompute:
```python
cache_service.set(CacheKeys.plan_summary(plan_id), new_data, CacheTTL.PLAN_SUMMARY)
```

#### CA3. `BaseRealtimeConsumer` Uses Raw Cache for Connection Tracking

```python
# shared/consumers.py
online_key = f"user_online:{self.user.id}"
cache.set(online_key, True, timeout=300)
```

This uses Django's cache directly instead of through `CachePort`, bypassing the abstraction layer.

#### CA4. Offline Event Caching Unbounded

```python
# shared/realtime_publisher.py
def _cache_event_for_offline_users(self, ...):
    cache_key = f"offline_events:{user_id}"
    events = cache.get(cache_key, [])
    events.append(event_data)
    cache.set(cache_key, events, timeout=86400)
```

Offline events are stored as a growing list with 24h TTL. If a user is offline for 24h with an active group, this list could grow unbounded within the TTL window. Should cap at a maximum (e.g., 100 events) or use Redis LIST with LTRIM.

---

## 8. Celery Async Architecture

**Score: 8.0/10**

### Queue Architecture

```python
CELERY_TASK_QUEUES = {
    'high_priority':  Exchange('high_priority'),   # Push notifications, real-time events
    'default':        Exchange('default'),          # General tasks
    'plan_status':    Exchange('plan_status'),      # Plan lifecycle (start/complete)
    'low_priority':   Exchange('low_priority'),     # Analytics, cleanup
}

CELERY_TASK_ROUTES = {
    'planpals.shared.tasks.send_push_notification_task': {'queue': 'high_priority'},
    'planpals.shared.tasks.send_event_push_notification_task': {'queue': 'high_priority'},
    'planpals.chat.infrastructure.tasks.fanout_chat_push_notification_task': {'queue': 'high_priority'},
    'planpals.plans.infrastructure.tasks.start_plan_task': {'queue': 'plan_status'},
    'planpals.plans.infrastructure.tasks.complete_plan_task': {'queue': 'plan_status'},
    'planpals.shared.analytics_tasks.*': {'queue': 'low_priority'},
}
```

### What Works

- **4 priority queues** properly segregate workloads
- **Idempotent tasks** — FCM deduplicates by message ID, plan status tasks check current state before acting
- **Exponential backoff** with jitter on all tasks
- **Rate limiting** — `200/m` on notification tasks
- **`acks_late=True`** for at-least-once delivery on critical tasks
- **`transaction.on_commit`** for task scheduling — tasks only dispatch after DB commit
- **Celery Beat schedule** with 3 periodic tasks:
  - `aggregate_daily_statistics_task` — daily 02:00
  - `cleanup_expired_offline_events_task` — daily 03:00
  - `cleanup_invalid_fcm_tokens_task` — weekly Sunday 04:00

### Issues

#### CE1. `PlanTaskScheduler` Stores Task IDs in DB

```python
# plans/infrastructure/task_scheduler.py
updates['scheduled_start_task_id'] = start_task.id
self._plan_repo.update_fields(plan.id, **updates)
```

Storing Celery task IDs in the DB for later revocation is fragile. If the broker loses the task (Redis flush, restart), the stored ID becomes stale. The revocation pattern also requires `celery.control.revoke()` which broadcasts to all workers.

**Alternative:** Use Celery Beat with dynamic schedule or check plan state at execution time (which `start_plan_task` already does — making the revocation redundant).

#### CE2. `fanout_chat_push_notification_task` Queries DB

```python
# chat/infrastructure/tasks.py
fcm_tokens = list(
    Conversation.objects.get(id=conversation_id)
    .participants.exclude(id=sender_id)
    .exclude(fcm_token__isnull=True)
    .values_list('fcm_token', flat=True)
)
```

This queries the DB inside the task. If the task retries after user changes FCM token, it correctly picks up the new token. But it adds DB load to the async path.

#### CE3. Single Redis Instance for Broker + Cache + Channels

Settings show:
```python
CELERY_BROKER_URL = REDIS_URL  # DB0
CACHES = {'default': {'LOCATION': f'{REDIS_URL}/1'}}  # DB1
CHANNEL_LAYERS = {'default': {'CONFIG': {'hosts': [REDIS_URL]}}}  # DB0
```

Celery broker and Channels share Redis DB0. Under high load, Celery task acknowledgments and WebSocket pub/sub can contend. In production, these should ideally be separate Redis instances.

---

## 9. RBAC Permission System

**Score: 7.5/10**

### Permission Matrix

| Permission Class | Applied To | Logic |
|-----------------|-----------|-------|
| `PlanPermission` | PlanViewSet | Creator ✅, group admin for writes, viewer for reads |
| `PlanActivityPermission` | PlanActivityViewSet | Plan creator or group admin for writes |
| `CanJoinPlan` | plan join action | Not creator, not already member, public plan or public group |
| `CanAccessPlan` | plan detail actions | Creator or group member |
| `CanModifyPlan` | plan mutation actions | Creator or group admin |
| `GroupPermission` | GroupViewSet | Admin for writes, member or public for reads, creator for delete |
| `IsGroupMember` | group member actions | `group.is_member(user)` |
| `IsGroupAdmin` | group admin actions | `group.is_admin(user)` |
| `UserProfilePermission` | user update | Only self can update |
| `CanViewUserProfile` | user retrieve | Delegates to `UserService.can_view_profile()` |
| `CanManageFriendship` | unfriend/block | Not self, must be friends for unfriend |
| `ChatMessagePermission` | ChatMessageViewSet | (Not fully defined — relies on queryset filtering) |

### What Works

- **`CanModifyPlan`** correctly restricts to creator or group admin (no is_member fallback — fixed in security audit)
- **`CanJoinPlan`** correctly checks group privacy
- **`DEFAULT_PERMISSION_CLASSES = [IsAuthenticated]`** — no unauthenticated access by default
- **`SendNotificationView`** restricted to `IsAdminUser`

### Issues

#### RBAC1. `ChatMessageViewSet.get_queryset()` Leaks Messages

```python
# chat/presentation/views.py
def get_queryset(self):
    return ChatMessage.objects.filter(
        conversation__group__members=self.request.user
    )
```

This only filters by `group` conversations. Direct messages (where `conversation.group` is NULL) are excluded — meaning the `search` and `recent` actions on `ChatMessageViewSet` only return group messages, not direct messages. This is a data visibility bug.

**Fix:**
```python
def get_queryset(self):
    user = self.request.user
    return ChatMessage.objects.filter(
        Q(conversation__group__members=user) |
        Q(conversation__user_a=user) |
        Q(conversation__user_b=user)
    ).select_related('sender', 'conversation', 'reply_to__sender')
```

#### RBAC2. `PlanActivityViewSet.create()` Has No Permission Enforcement

The `create()` method inherits from `CreateModelMixin` which uses `PlanActivityPermission.has_permission()`. This checks if the user can modify the plan referenced by `request.data.get('plan')`. But the `plan` field in `PlanActivityCreateSerializer` is `plan_id` (UUID), while the permission checks `request.data.get('plan')` — field name mismatch.

#### RBAC3. `GroupViewSet.send_message()` Double-Checks Membership

```python
# groups/presentation/views.py
@action(detail=True, methods=['post'], permission_classes=[IsAuthenticated, IsGroupMember])
def send_message(self, request, pk=None):
    group = self.get_object()
    if not group.members.filter(id=request.user.id).exists():  # REDUNDANT
        return Response({'error': 'You are not a member'}, ...)
```

`IsGroupMember` already enforces membership via `has_object_permission()`, so the explicit check is redundant and adds an extra DB query.

#### RBAC4. `ConversationViewSet` Access Checks Use Private Method

```python
# chat/presentation/views.py
if not ConversationService._can_user_access_conversation(request.user, conversation):
```

Views call a private method (`_can_user_access_conversation`) on the service. This should be a proper permission class:

```python
class CanAccessConversation(BasePermission):
    def has_object_permission(self, request, view, obj):
        return ConversationService.can_user_access_conversation(request.user, obj)
```

---

## 10. OAuth2 Security

**Score: 7.0/10**

### Configuration

```python
OAUTH2_PROVIDER = {
    'ACCESS_TOKEN_EXPIRE_SECONDS': 3600,         # 1 hour
    'REFRESH_TOKEN_EXPIRE_SECONDS': 604800,       # 1 week
    'ROTATE_REFRESH_TOKENS': True,                # New refresh token on each refresh
    'ALLOWED_REDIRECT_URI_SCHEMES': ['https', 'planpal'],
    'OAUTH2_BACKEND_CLASS': 'oauth2_provider.backends.OAuthLibCore',
    'SCOPES': {'read': 'Read scope', 'write': 'Write scope'},
}
```

### What Works

- **Refresh token rotation** — each refresh grants a new refresh token, invalidating the old one
- **1-hour access token** — reasonable expiry
- **`DEFAULT_PERMISSION_CLASSES = [IsAuthenticated]`** — global authentication required
- **`DEBUG` env-driven** — `DEBUG = os.environ.get('DEBUG', 'False').lower() == 'true'`
- **`CORS_ALLOW_ALL_ORIGINS` conditional on DEBUG** — restrictive in production
- **Swagger gated behind DEBUG** — API docs not exposed in production
- **WebSocket auth via OAuth2 token** — `BaseRealtimeConsumer` validates query string token

### Issues

#### OA1. `GRANT_TYPE = 'password'` Used

The OAuth2 flow uses Resource Owner Password Credentials grant type. This is deprecated in OAuth 2.1 and exposes user credentials to the client app. For a mobile app, Authorization Code with PKCE is preferred.

However, for a university project with a self-managed Flutter client, password grant is pragmatically acceptable.

#### OA2. WebSocket Token Validation Missing Expiry Check

```python
# shared/consumers.py (BaseRealtimeConsumer)
async def _authenticate_user(self, token_string):
    token = await database_sync_to_async(
        AccessToken.objects.select_related('user').get
    )(token=token_string)
    if token.is_expired():
        await self.close(code=4001)
        return None
    return token.user
```

This checks expiry at connection time but doesn't re-validate during long-lived WebSocket connections. A token that expires during an active session remains valid until disconnect.

**Fix:** Add periodic token validation or rely on short-lived access tokens + client-side reconnection.

#### OA3. No CSRF Protection on OAuth2 Endpoints

DRF views use `SessionAuthentication` for CSRF by default, but OAuth2 endpoints (`/o/token/`, `/o/revoke_token/`) use their own CSRF handling. Since the app is API-only with Bearer token auth, CSRF is not a primary concern, but the OAuth2 token endpoint could be vulnerable if sessions are used.

#### OA4. FCM Token Not Scoped

FCM tokens are stored as a single field on the User model:
```python
fcm_token = models.CharField(max_length=255, blank=True, null=True)
```

Only one device token per user. If a user has multiple devices, only the last registered device receives push notifications.

**Fix:** Create a `DeviceToken` model with `user`, `token`, `platform`, `created_at`.

---

## 11. Dead Code Detection

**Score: Findings below**

### Dead/Unused Code

| Item | Location | Evidence | Severity |
|------|----------|----------|----------|
| `SendMessageHandler` | `chat/application/handlers.py` | Never called — `ConversationService.create_message()` is used instead | HIGH |
| `UpdateGroupCommand` | `groups/application/commands.py` | No corresponding handler exists | MEDIUM |
| `DjangoUnitOfWork` | `shared/infrastructure.py` | Defined but zero usages across all handlers | HIGH |
| `BaseService.validate_user_permission()` | `shared/base_service.py` | Always returns True — stub | LOW |
| `User.friends` property | `auth/infrastructure/models.py` | Buggy (`self.objects`) — if called, would crash | MEDIUM |
| `FriendsListSerializer` | `auth/presentation/serializers.py` | Not imported by any view — `FriendsListView` uses `UserSummarySerializer` | LOW |
| `ConversationSummarySerializer` | `chat/presentation/serializers.py` | Not imported by any view | LOW |
| `PlanActivitySummarySerializer` | `plans/presentation/serializers.py` | Not imported by any view | LOW |
| `ManualCursorPaginator.paginate_by_datetime()` | `shared/paginators.py` | Only `paginate_by_id` appears to be used | LOW |
| `is_local_path()` helper | `plans/application/services.py` | Module-level utility — unclear if used | LOW |
| `CanNotTargetSelf` | `auth/presentation/permissions.py` | Defined but not assigned to any view | LOW |
| `FriendshipPermission` | `auth/presentation/permissions.py` | Defined but not used by any viewset action | MEDIUM |

### Partially Dead Code

| Item | Location | Issue |
|------|----------|-------|
| `BaseCommand` | `shared/interfaces.py` | Auth commands don't inherit from it |
| `MembershipRole.CHOICES` | `groups/domain/entities.py` | Non-standard attribute on str,Enum |
| `PlanCreateSerializer.create()` | `plans/presentation/serializers.py` | Overrides ModelSerializer.create(), but PlanViewSet.perform_create() calls PlanService instead |

---

## 12. Dead File Detection

**Score: Findings below**

### Files Assessment

| File | Status | Notes |
|------|--------|-------|
| `planpals/models.py` | ACTIVE — facade | Re-exports all models for Django admin + Celery tasks |
| `planpals/tasks.py` | ACTIVE — facade | Re-exports all tasks for Celery discovery |
| `planpals/admin.py` | UNKNOWN | Not audited — likely registers models for Django admin |
| `notifications/application/services.py` | DOES NOT EXIST | notifications is a thin context — views only |
| `notifications/infrastructure/models.py` | DOES NOT EXIST | No models — notifications are via FCM only |
| `locations/application/services.py` | DOES NOT EXIST | locations is a thin context — views + GoongMapService only |
| `locations/infrastructure/models.py` | DOES NOT EXIST | No models — location data from external API |
| `chat/application/factories.py` | DOES NOT EXIST | Chat context has no factory file — handlers created inline |
| `auth/infrastructure/oauth2_utils.py` | UNKNOWN | Imported in views (`OAuth2ResponseFormatter`) — likely active |
| `planpals/integrations/base_service.py` | ACTIVE | Base class for `NotificationService` |

### Redundant Dual Systems

**Domain Events vs. Realtime Publisher:**

Two parallel event publishing systems exist:

1. **Domain Event pipeline:** Handler → `ChannelsDomainEventPublisher.publish()` → `transaction.on_commit` → `_event_registry.dispatch_event()` → registered handlers
2. **Realtime Publisher:** Service → `RealtimeEventPublisher.publish_new_message()` → WebSocket broadcast + push notification

The chat context uses system 2 exclusively. Plans and groups use system 1 through handlers. This creates architectural inconsistency.

**Recommendation:** Unify on the domain event pipeline. Register realtime publishing as event handlers:

```python
# shared/_event_registry.py
register_event_handler('PlanCreated', lambda event: publish_plan_created(event))
register_event_handler('MessageCreated', lambda event: publish_new_message(event))
```

---

## 13. Scalability Analysis

**Score: 6.5/10**

### Current Bottlenecks

#### S1. Single MySQL Instance

No read replicas configured. All reads and writes go to the same database. For a university project this is fine; for production scale the `get_queryset()` methods in ViewSets should route reads to replicas.

#### S2. Redis Single Instance (3 Roles)

Redis serves as:
1. Celery broker (DB0)
2. Django cache (DB1)  
3. Channels layer (DB0)

Under high WebSocket message throughput + push notification load + cache operations, a single Redis instance becomes the bottleneck.

#### S3. Chat Message Table Growth

`ChatMessage` stores all messages with soft delete. Over time:
- Cursor pagination performance degrades without composite index `(conversation_id, created_at DESC)`
- `get_unread_count()` scans grow
- The `search` action uses `content__icontains` which does full table scan

**Recommendations:**
- Add composite index
- Partition by date or conversation
- Use full-text search (MySQL FULLTEXT or Elasticsearch) instead of `LIKE %query%`

#### S4. Synchronous Realtime Publishing

```python
# shared/realtime_publisher.py
def publish_event(self, event):
    self._send_to_websocket(event)        # Sync channel_layer.group_send
    self._send_push_notification(event)    # Dispatches Celery task
    self._cache_event_for_offline_users(event)  # Cache write
```

`_send_to_websocket()` calls `async_to_sync(channel_layer.group_send)()` which blocks the request thread until the message is sent to Redis. Under high throughput, this blocks Django worker threads.

**Fix:** Make WebSocket publishing async or dispatch via Celery:
```python
@shared_task
def publish_websocket_event_task(channel_group, event_data):
    channel_layer = get_channel_layer()
    async_to_sync(channel_layer.group_send)(channel_group, event_data)
```

#### S5. `aggregate_daily_statistics_task` Does Full Table Scans

```python
# shared/analytics_tasks.py
today_plans = Plan.objects.filter(created_at__date=today)
today_groups = Group.objects.filter(created_at__date=today)
today_users = User.objects.filter(date_joined__date=today)
```

For a growing dataset, date-based queries without covering indexes will slow down. Add `db_index=True` on `date_joined` (already exists on `created_at` via `BaseModel`).

#### S6. No Connection Pooling Configured

Settings don't show explicit MySQL connection pooling (`CONN_MAX_AGE` or `django-mysql-pool`). Default Django behavior creates a new DB connection per request.

**Fix:**
```python
DATABASES['default']['CONN_MAX_AGE'] = 600  # Reuse connections for 10 minutes
```

### Scalability Roadmap

| Priority | Action | Impact |
|----------|--------|--------|
| P0 | Add `@transaction.atomic` to handlers | Data consistency |
| P0 | Fix `ChatMessageViewSet.get_queryset()` DM visibility | Correctness |
| P1 | Add composite index on `ChatMessage(conversation_id, created_at)` | Query perf |
| P1 | Set `CONN_MAX_AGE = 600` | Connection reuse |
| P1 | Separate Redis instances (broker / cache / channels) | Reliability |
| P2 | Async WebSocket publishing via Celery | Worker thread relief |
| P2 | Cache conversation unread counts | Reduce DB load |
| P3 | MySQL read replicas | Read scalability |
| P3 | Full-text search for chat messages | Search performance |

---

## 14. Final Optimized Architecture

### Current Architecture Score

| Dimension | Score | Weight | Weighted |
|-----------|-------|--------|----------|
| Clean Architecture | 6.5 | 15% | 0.975 |
| Dependency Rules | 6.0 | 10% | 0.600 |
| Bounded Contexts | 7.0 | 10% | 0.700 |
| Domain Logic | 6.0 | 10% | 0.600 |
| Command Handlers | 6.5 | 10% | 0.650 |
| DB Performance | 7.5 | 10% | 0.750 |
| Redis Cache | 7.5 | 10% | 0.750 |
| Celery Async | 8.0 | 5% | 0.400 |
| RBAC Permissions | 7.5 | 10% | 0.750 |
| OAuth2 Security | 7.0 | 5% | 0.350 |
| Dead Code | N/A | 2.5% | N/A |
| Dead Files | N/A | 2.5% | N/A |
| **TOTAL** | | **100%** | **6.525 → 6.5/10** |

### Top 10 Critical Fixes (Priority-Ordered)

1. **Add `@transaction.atomic` to all mutating handlers** — prevent partial mutations
2. **Fix `ChatMessageViewSet.get_queryset()`** — include direct message conversations
3. **Fix `User.friends` property bug** — `self.objects` → `User.objects`
4. **Remove `DjangoUserRepository.update_profile()` serializer import** — move validation to application layer
5. **Delete dead `SendMessageHandler`** or route `ConversationService.create_message()` through it
6. **Create `UpdateGroupHandler`** for the orphaned `UpdateGroupCommand`
7. **Add domain events to chat context** — `MessageCreated`, `MessageEdited`, `MessageDeleted`
8. **Make auth commands extend `BaseCommand`** — consistency
9. **Move `ChatMessage.save()` side effects to service layer** — model should only persist
10. **Remove `UserService.join_group()` direct import** — use cross-context interface

### Target Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Presentation Layer                         │
│  Views → Serializers → Permissions                           │
│  (DRF ViewSets, only knows application layer interfaces)     │
├─────────────────────────────────────────────────────────────┤
│                    Application Layer                         │
│  Commands → Handlers (with UoW) → Domain Events             │
│  Services (thin orchestration, @classmethod → eliminated)    │
│  Factories (composition root, cross-context wiring)          │
├─────────────────────────────────────────────────────────────┤
│                      Domain Layer                            │
│  Entities (pure Python, enums, value objects)                │
│  Repository ABCs (typed return values, not Any)              │
│  Domain Events (frozen dataclasses)                          │
│  Domain Services (stateless business rules)                  │
├─────────────────────────────────────────────────────────────┤
│                   Infrastructure Layer                       │
│  ORM Models (persistence only, no business logic)            │
│  Django Repositories (implement domain ABCs)                 │
│  Celery Tasks (async jobs)                                   │
│  Event Handlers (subscribe to domain events)                 │
│  External Services (FCM, Goong, Cloudinary)                  │
└─────────────────────────────────────────────────────────────┘
```

### Key Architectural Improvements

1. **Eliminate Service Layer Ambiguity:**
   - Views call factories → get handlers → `handler.handle(command)`
   - Remove `PlanService`, `GroupService`, `UserService` classmethod-based services
   - Or: Keep services as thin facade over handlers (current pattern, just enforce consistency)

2. **Unify Event Systems:**
   - All domain events flow through `ChannelsDomainEventPublisher` → `_event_registry`
   - Register realtime publishing as event handlers, not direct calls
   - Chat context publishes `MessageCreated` events like all other contexts

3. **Enforce UnitOfWork:**
   - All mutating handlers wrapped in `@transaction.atomic` or `DjangoUnitOfWork`
   - Domain events published via `on_commit` callbacks (already done in `ChannelsDomainEventPublisher`)

4. **Type Repository Returns:**
   - Replace `Any` return types with domain entity types or typed DTOs
   - Example: `def get_by_id(self, plan_id: UUID) -> Optional[PlanEntity]`

5. **Centralize Cross-Context Wiring:**
   - Move all factory files to a single `planpals/composition_root.py`
   - Or: Keep per-context factories but prohibit cross-context infrastructure imports

### Estimated Post-Fix Score: **7.5-8.0/10**

---

## Fixes Applied

The following critical fixes from this audit have been implemented:

| # | Fix | Status | Files Modified |
|---|-----|--------|----------------|
| 1 | `@transaction.atomic` on all mutating handlers | ✅ DONE | `plans/application/handlers.py`, `groups/application/handlers.py`, `auth/application/handlers.py` |
| 2 | `ChatMessageViewSet.get_queryset()` DM visibility | ✅ DONE | `chat/presentation/views.py` |
| 3 | `User.friends` property bug (`self.objects` → `User.objects`) | ✅ DONE | `auth/infrastructure/models.py` |
| 4 | Remove serializer import from infrastructure layer | ✅ DONE | `auth/infrastructure/repositories.py` — replaced DRF serializer with direct ORM `update_fields` |
| 5 | Delete dead `SendMessageHandler` | ✅ DONE | `chat/application/handlers.py`, `chat/application/factories.py` |
| 6 | Create `UpdateGroupHandler` for orphaned command | ✅ DONE | `groups/application/handlers.py`, `groups/application/factories.py` |
| 7 | Add chat domain events | ✅ DONE | Created `chat/domain/events.py` with `MessageSent`, `MessageEdited`, `MessageDeleted`, `MessagesRead`, `ConversationCreated` |
| 8 | Auth commands extend `BaseCommand` | ✅ DONE | `auth/application/commands.py` |

### Remaining Fixes (Not Yet Applied)

| # | Fix | Priority |
|---|-----|----------|
| 9 | Move `ChatMessage.save()` side effects to service layer | MEDIUM |
| 10 | Remove `UserService.join_group()` direct import — use cross-context interface | LOW |

### Validated

- `python manage.py check` — passes (only pre-existing CKEditor warning)
- All module imports validated successfully

---

*End of Deep Architecture Audit*
