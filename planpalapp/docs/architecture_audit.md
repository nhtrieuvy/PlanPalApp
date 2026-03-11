# PlanPal Backend — Comprehensive Architecture Audit

**Date:** 2025  
**Scope:** `planpalapp/` — Django 5.2.6 + DRF 3.14.0 + MySQL + Redis + Celery 5.3.1  
**Reviewer perspective:** Principal Engineer — Production Backend Review

---

## 1. Executive Summary

The PlanPal backend implements a **credible Clean Architecture** with four bounded contexts (`plans`, `groups`, `auth`, `chat`), each structured as `domain/ → application/ → infrastructure/ → presentation/`. Domain layers are pure Python with no framework dependencies. Application handlers use repository interfaces. Factories serve as composition roots. Redis caching and Celery async processing are well-integrated.

**Architecture Maturity:** 7/10 — Strong structural foundation with meaningful violations that would cause production incidents under load.

### Critical Findings (must fix)

| # | Finding | Severity | Impact |
|---|---------|----------|--------|
| 1 | `DEBUG = True` and `ALLOWED_HOSTS = ['*']` in deployed settings | **CRITICAL** | Full stack traces, SQL queries, and debug info exposed to attackers |
| 2 | `shared/exceptions.py` extends `rest_framework.exceptions.APIException` — all handlers importing these have a framework dependency | **HIGH** | Clean Architecture Dependency Rule violated across all bounded contexts |
| 3 | `CORS_ALLOW_ALL_ORIGINS = True` overrides `CORS_ALLOWED_ORIGINS` | **HIGH** | Any origin can make credentialed requests |
| 4 | No DRF throttle classes configured | **HIGH** | Zero rate limiting on API endpoints — trivially DDoS-able |
| 5 | `firebase_service_account.json` committed to repo | **HIGH** | Credential exposure if repo becomes public |
| 6 | Validation logic duplicated between domain `entities.py` and presentation `serializers.py` | **MEDIUM** | Business rule drift — serializer and domain diverge silently |
| 7 | Dead code in `GroupViewSet` (unreachable returns) | **MEDIUM** | Indicates missed testing coverage |

### Strengths

- Pure Python domain layers with zero Django/DRF imports  
- Repository interface pattern consistently applied across all 4 contexts  
- Factory composition roots isolate infrastructure wiring  
- Celery task architecture with 4 priority queues, retry policies, time limits  
- Cache stampede prevention with lock-based `get_or_set`  
- Optimistic locking on `PlanActivity` via version field  

---

## 2. Clean Architecture Compliance

### 2.1 Domain Layer (Innermost) — Score: 9.5/10

All four bounded contexts have clean domain layers:

| Context | File | Django Imports? | Status |
|---------|------|----------------|--------|
| plans | `domain/entities.py` | None | ✅ Pure Python enums + validation functions |
| plans | `domain/repositories.py` | None | ✅ ABCs with `Any` return types |
| plans | `domain/events.py` | None | ✅ Frozen dataclasses, depends only on `shared.interfaces.DomainEvent` |
| groups | `domain/entities.py` | None | ✅ Pure `MembershipRole` enum |
| groups | `domain/repositories.py` | None | ✅ ABCs for `GroupRepository`, `GroupMembershipRepository` |
| groups | `domain/events.py` | None | ✅ Frozen dataclasses |
| auth | `domain/entities.py` | None | ✅ `FriendshipStatus` enum + `can_resend_after_rejection()` pure function |
| auth | `domain/repositories.py` | None | ✅ ABCs for `UserRepository`, `FriendshipRepository`, `TokenRepository` |
| auth | `domain/events.py` | None | ✅ Frozen dataclasses |
| chat | `domain/entities.py` | None | ✅ `ConversationType`, `MessageType` enums + validation |
| chat | `domain/repositories.py` | None | ✅ ABCs for `ConversationRepository`, `ChatMessageRepository` |

**Minor deduction (−0.5):** `groups/domain/entities.py` is only 27 lines with a single enum. The `MembershipRole.CHOICES` is defined as a class attribute rather than deriving from the enum — this is a code smell (defining Django-style choices inside a domain entity), though technically no Django import exists.

### 2.2 Application Layer — Score: 8/10

**Commands:** All frozen dataclasses. No framework dependencies. ✅  
**Handlers:** All depend on domain repository interfaces. No ORM imports. ✅  
**Factories:** Correctly serve as composition roots — the ONLY place importing infrastructure into the application layer. ✅

**Violations found:**

**V1: `shared/exceptions.py` inherits from `rest_framework.exceptions.APIException`**

```python
# shared/exceptions.py — line 7-8
from rest_framework.exceptions import APIException
class PlanPalException(APIException): ...
```

Every handler across all four bounded contexts imports from this module:
```python
# groups/application/handlers.py — line 22
from planpals.shared.exceptions import GroupNotFoundException, NotGroupAdminException, ...
```

This means **all application-layer handlers have a transitive dependency on DRF**, violating the Dependency Rule. The domain/application layers should define their own pure Python exception hierarchy. The presentation layer can catch and translate these into DRF-compatible responses.

**V2: `PlanService` imports `RealtimeEvent` from `shared/events.py`**

```python
# shared/events.py — line 8
from django.utils import timezone  # Django import in shared module
```

`PlanService.start_trip()` and `complete_trip()` directly construct `RealtimeEvent` objects and call `publisher.publish_event()`, bypassing the handler/domain-event pattern used everywhere else. This is both a dependency violation and an architectural inconsistency.

**V3: `PlanService` is 631 lines — still a "god service"**

Despite delegating mutations to handlers, the service retains significant query-coordination logic, cache invalidation, and direct event publishing. Services in groups (230 lines), auth (400 lines), and chat (350 lines) are more appropriately sized.

### 2.3 Infrastructure Layer — Score: 9/10

ORM models correctly live in `infrastructure/models.py`. Repository implementations use `select_related()` and `prefetch_related()` appropriately. The `ChannelsDomainEventPublisher` properly defers event dispatch via `transaction.on_commit()`.

**Issue:** `Plan.save()` and `PlanActivity.save()` contain business logic that should live in handlers:

```python
# Plan.save() — auto_status(), celery task scheduling, date-change detection
def save(self, *args, **kwargs):
    self.plan_type = 'personal' if self.group is None else 'group'
    status_changed = self._auto_status()
    ...
    if is_new or dates_changed:
        self.schedule_celery_tasks()
```

This makes the ORM model an active participant in business logic — in strict Clean Architecture, the model should be a passive data container. The handler should compute the auto-status and schedule tasks.

### 2.4 Presentation Layer — Score: 7.5/10

Views correctly delegate mutations to service layer. Queryset optimizations are applied (`select_related`, `prefetch_related`, `with_stats()`).

**Issues:**

1. **Validation duplication:** `PlanActivitySerializer.validate()` re-implements date, coordinate, and cost validation that already exists in `domain/entities.py` (`validate_plan_dates()`, `validate_coordinates()`, `validate_estimated_cost()`). If domain rules change, the serializer must be updated separately.

2. **ORM query in serializer:** `PlanActivityCreateSerializer.validate()` performs `Plan.objects.get(id=plan_id)` — an infrastructure concern leaking into serializer validation.

3. **Duplicate endpoints:** `PlanViewSet` has both `add_activity` and `create_activity` actions performing the same operation.

---

## 3. Dependency Rule Violations

The Dependency Rule states: **source code dependencies must point inward** (Presentation → Application → Domain). No inner layer should know about an outer layer.

### Violation Map

```
Domain Layer
  ✅ entities.py — pure Python
  ✅ repositories.py — pure ABCs
  ✅ events.py — pure dataclasses

Application Layer
  ❌ handlers.py → imports shared/exceptions.py → depends on DRF (APIException)
  ⚠️ services.py → imports shared/events.py → depends on django.utils.timezone
  ✅ commands.py — pure dataclasses
  ✅ factories.py — composition root (infra imports are correct here)

Infrastructure Layer
  ✅ models.py — Django ORM (correct layer)
  ✅ repositories.py — implements domain interfaces
  ⚠️ Plan.save() contains business logic (auto-status, scheduling)

Presentation Layer
  ⚠️ serializers duplicate domain validation
  ⚠️ serializers perform ORM queries
```

### Recommended Fix for Error Hierarchy

```python
# shared/domain_exceptions.py (NEW — pure Python)
class PlanPalDomainError(Exception):
    def __init__(self, message: str, code: str = 'error'):
        self.message = message
        self.code = code
        super().__init__(message)

class NotFoundError(PlanPalDomainError): ...
class PermissionError(PlanPalDomainError): ...
class BusinessRuleError(PlanPalDomainError): ...

# shared/exception_handler.py — map domain errors to DRF responses
def custom_exception_handler(exc, context):
    if isinstance(exc, PlanPalDomainError):
        return Response({'error': exc.message, 'code': exc.code}, status=...)
```

---

## 4. Database & Query Performance

### 4.1 Index Analysis

**Plan model — 6 composite indexes:**

| Index | Purpose | Verdict |
|-------|---------|---------|
| `(creator, plan_type, status)` | User's plans filtered by type/status | ✅ Good |
| `(group, status)` | Group plans by status | ✅ Good |
| `(start_date, end_date)` | Date range queries | ✅ Good |
| `(is_public, plan_type, status)` | Public plan discovery | ✅ Good |
| `(status, start_date)` | Status + date filter | ✅ Good |
| `(status, end_date)` | Auto-status detection | ✅ Good |

**PlanActivity — 3 composite indexes:**

| Index | Purpose | Verdict |
|-------|---------|---------|
| `(plan, start_time)` | Activities for plan ordered by time | ✅ Good |
| `(activity_type, start_time)` | Activities by type | ✅ Good |
| `(plan, start_time, end_time)` | Time conflict detection | ✅ Good — covers the `filter(start_time__lt=end_time, end_time__gt=start_time)` pattern |

**GroupMembership — 2 composite indexes:**

| Index | Purpose | Verdict |
|-------|---------|---------|
| `(group, role)` | Members of group by role | ✅ Good |
| `(user, role)` | Groups of user by role | ✅ Good |

**User — 2 composite indexes:**

| Index | Purpose | Verdict |
|-------|---------|---------|
| `(first_name, last_name)` | Name search | ✅ Good |
| `(is_online, last_seen)` | Online user queries | ✅ Good |

**BaseModel inherited indexes:** `[created_at]` on all tables + `is_active` (single-column, via `db_index=True`).

### 4.2 Query Concerns

**C1: `Plan.save()` self-query for date change detection**

```python
# Plan.save() — line ~230
old_plan = Plan.objects.only('start_date', 'end_date').get(pk=self.pk)
```

Every plan save performs an extra SELECT to check if dates changed. This should be handled by the handler comparing old/new values before calling `save()`.

**C2: `PlanActivity.__str__()` triggers lazy FK load**

```python
def __str__(self):
    return f"{self.plan.title} - {self.title}"  # self.plan is not select_related
```

When iterating activities in admin or logging, this causes N+1 queries.

**C3: `Group.save()` performs 2-3 extra queries**

```python
def save(self, *args, **kwargs):
    super().save(...)
    if is_new:
        GroupMembership.objects.get_or_create(...)  # +1 query
        Conversation.objects.create(...)            # +1 query
```

Side-effect creation inside `save()` is an anti-pattern. These should be handled by the `CreateGroupHandler`.

**C4: `Group.is_member()` / `Group.is_admin()` always hit DB**

```python
def is_member(self, user):
    return GroupMembership.objects.filter(group=self, user=user).exists()
```

These are called frequently (permission checks, serializer methods) but never check for prefetched data. The serializer works around this with `_get_user_membership()`, but callers outside serializers (e.g., handlers) always hit the DB.

**C5: `User.unread_messages_count` — complex subquery**

```python
@property
def unread_messages_count(self):
    # 30s cache, then:
    unread_messages = ChatMessage.objects.filter(
        conversation__in=user_conversations,
        is_deleted=False
    ).exclude(sender=self).exclude(
        Exists(MessageReadStatus.objects.filter(message=OuterRef('pk'), user=self))
    )
```

This involves a subquery with `EXISTS` across three tables. The 30-second cache mitigates, but under high message volume this can be slow. Consider maintaining a denormalized counter.

### 4.3 Missing Indexes

| Table | Suggested Index | Reason |
|-------|----------------|--------|
| `Friendship` | `(user_a, user_b, status)` | Friendship lookups always filter both users + status |
| `ChatMessage` | `(conversation, created_at, is_deleted)` | Message pagination query pattern |
| `MessageReadStatus` | `(message, user)` | EXISTS subquery in unread count |

---

## 5. Caching Architecture

### 5.1 Current Cache Points

| Endpoint | TTL | Stampede Prevention | Invalidation |
|----------|-----|-------------------|--------------|
| User Profile | 120s | ✅ Lock-based | ✅ On profile update, friend accept/reject |
| Plan Summary | 180s | ✅ Lock-based | (manual via service) |
| Group Detail | 180s | ✅ Lock-based | ✅ On member add/remove/promote/demote |

### 5.2 Cache Design Strengths

- `CachePort` abstraction allows swapping Redis for another backend ✅
- Versioned cache keys (`v1:user:profile:{id}`) — bump version when data shape changes ✅
- Pattern-based invalidation for group cache (user-specific variants) ✅
- Stampede prevention via `cache.add()` lock — correctly double-checks after acquiring lock ✅

### 5.3 Cache Gaps

**G1: `User.unread_messages_count` uses raw `cache.get/set` instead of `CachePort`**

```python
# auth/infrastructure/models.py
cache_key = f"user_unread_count_{self.id}"
cached_count = cache.get(cache_key)
```

This bypasses the `CachePort` abstraction and the versioned key pattern. If Redis is down, this will throw an exception instead of gracefully falling back.

**G2: No caching on membership checks**

`Group.is_member()` and `Group.is_admin()` are called during every permission check but never cached. For high-traffic group endpoints, this means one `SELECT EXISTS` per request.

**G3: Offline event cache uses uncontrolled growth**

```python
# realtime_publisher.py
cached_events.append(event.to_dict())
if len(cached_events) > 50:
    cached_events = cached_events[-50:]
cache.set(cache_key, cached_events, timeout=86400)
```

The list is deserialized, modified, and re-serialized on every event — O(n) per event publication. For users receiving many real-time events, this becomes a bottleneck. Consider using Redis `LPUSH` + `LTRIM` directly.

---

## 6. Async Processing (Celery)

### 6.1 Architecture — Score: 9/10

| Aspect | Status |
|--------|--------|
| 4 priority queues | ✅ `high_priority`, `default`, `plan_status`, `low_priority` |
| Task routing | ✅ Every task mapped to the correct queue |
| Retry with exponential backoff | ✅ `retry_backoff=True`, `retry_backoff_max=120` |
| Jitter | ✅ `retry_jitter=True` — prevents thundering herd |
| Time limits | ✅ Soft: 120s, Hard: 300s (overridden per-task) |
| Rate limiting | ✅ Per-task rate limits (200/m for push, 1/h for analytics) |
| Worker recycling | ✅ `WORKER_MAX_TASKS_PER_CHILD = 200` |
| Late ACK | ✅ `CELERY_TASK_ACKS_LATE = True` — re-deliver on crash |
| Reject on lost | ✅ `CELERY_TASK_REJECT_ON_WORKER_LOST = True` |
| Observability | ✅ Signal handlers for `task_failure`, `task_retry`, `task_success` |
| Periodic tasks | ✅ 3 Celery Beat jobs (daily stats, cleanup offline events, cleanup FCM tokens) |

### 6.2 Concerns

**C1: `send_event_push_notification_task` does heavy DB work**

This task resolves push notification targets (queries Plan members, Group members, etc.) from within the Celery worker. If the DB is slow or the member list is large, this can timeout. Consider pre-computing the target list in the request cycle and passing FCM tokens directly.

**C2: No dead-letter queue (DLQ)**

After `max_retries` exhaustion, failed tasks are silently dropped. Consider routing failed tasks to a DLQ for investigation.

**C3: Visibility timeout vs. ETA**

```python
'visibility_timeout': 3600  # 1h
```

Plan lifecycle tasks use ETA scheduling (e.g., schedule start_plan_task at plan's start_date). If the ETA is > 1 hour in the future, the visibility timeout must exceed the ETA difference, or Redis will redeliver the message. For plans scheduled days ahead, 3600s is insufficient. Consider using `django-celery-beat` with database-backed scheduling for long-horizon ETAs.

---

## 7. Scalability Risks

### 7.1 Single Redis Instance

```python
CELERY_REDIS_URL = 'redis://127.0.0.1:6379/0'
CACHES = {'default': {'LOCATION': 'redis://127.0.0.1:6379/1'}}
CHANNEL_LAYERS = {'default': {'CONFIG': {'hosts': [CELERY_REDIS_URL]}}}
```

All three subsystems (Celery broker, Django cache, Channels) share a single Redis instance. If Redis goes down:
- Celery stops processing tasks
- Cache operations fail (gracefully, due to `DjangoCacheService` error handling)
- WebSocket broadcasting fails
- **No failover, no replication**

**Recommendation:** Use Redis Sentinel or managed Redis (e.g., Amazon ElastiCache) with separate instances for Celery vs. Cache/Channels.

### 7.2 Stateful WebSocket on Single Server

The `BaseRealtimeConsumer` uses `channels_redis` for group messaging. With a single Daphne/ASGI server (as suggested by `fly.toml`), this works. When horizontally scaling to multiple instances, ensure all instances share the same Redis channel layer — which they do via configuration, but the `track_connection()` cache-based tracking won't work across instances.

### 7.3 `GroupCreateSerializer.create()` — O(N) queries for initial members

```python
for user_id in initial_members:
    user = User.objects.get(id=user_id)        # +1 query
    GroupService.add_member(group, user, ...)   # +1-3 queries per member
```

Creating a group with 10 members = ~40 queries. Should batch-fetch users and batch-create memberships.

### 7.4 No Database Connection Pooling

```python
DATABASES = {'default': dj_database_url.config(conn_max_age=600, ...)}
```

`conn_max_age=600` keeps connections alive for 10 minutes, which helps. However, under Daphne (ASGI), connections aren't pooled the same way as WSGI. Consider using `django-db-connection-pool` or PgBouncer/ProxySQL for MySQL.

---

## 8. Code Organization & Quality

### 8.1 Dead Code

**GroupViewSet.created_by_me — unreachable return:**

```python
# groups/presentation/views.py
def created_by_me(self, request):
    ...
    serializer = self.get_serializer(queryset, many=True)
    return Response(serializer.data)       # ← returns here
    return Response({                       # ← DEAD CODE
        'groups': serializer.data,
        'count': len(serializer.data)
    })
```

**GroupViewSet.recent_messages — duplicate code block:**

```python
def recent_messages(self, request, pk=None):
    group = self.get_object()
    serializer = ChatMessageSerializer(...)
    return Response({...})                 # ← returns here
    group = self.get_object()              # ← DEAD CODE (entire block repeated)
    ...
```

### 8.2 Inconsistencies

| Issue | Location |
|-------|----------|
| Auth commands don't extend `BaseCommand` | `auth/application/commands.py` — `SendFriendRequestCommand` is `@dataclass(frozen=True)` without inheriting `BaseCommand` |
| `_get_duration_display` duplicated | Both `PlanSerializer` and `PlanSummarySerializer` have identical implementations |
| `_get_group_initials` duplicated 3x | `GroupSerializer`, `GroupCreateSerializer`, `GroupSummarySerializer` |
| Mixed language in error messages | Some views return Vietnamese ("Không tìm thấy người dùng"), others English ("User not found") |
| `EnhancedPlanViewSet` / `EnhancedGroupViewSet` | Single-method subclasses — should be merged into parent viewsets |

### 8.3 Bounded Context Coupling

| Cross-Context Import | Location | Assessment |
|---------------------|----------|------------|
| Groups → Auth repos | `groups/application/factories.py` → `DjangoFriendshipRepository` | ⚠️ Cross-context infra coupling — should use domain interface |
| Groups → Chat repos | `groups/application/factories.py` → `DjangoConversationRepository` | ⚠️ Same issue |
| Auth → Groups service | `auth/application/services.py` → `GroupService.join_group_by_invite()` | ⚠️ Service-level cross-context coupling |
| Groups views → Chat | `groups/presentation/views.py` → `ChatService`, `ChatMessageSerializer` | ⚠️ Presentation cross-context coupling |
| Groups views → Auth | `groups/presentation/views.py` → `UserSerializer` | Acceptable — read-only serializer reuse |

The cross-context coupling in `factories.py` should be mediated through Anti-Corruption Layer interfaces defined in the consuming context's domain layer. For example, `groups/domain/repositories.py` should define a `FriendshipChecker` interface, and `factories.py` should wire in the concrete implementation.

---

## 9. Observability & Reliability

### 9.1 Logging — Score: 7/10

- `BaseService.log_operation()` provides structured operation logging ✅
- Celery signal handlers log failures, retries, successes ✅
- File + console logging configured ✅

**Gaps:**
- Root logger at `DEBUG` level — too verbose for production
- No request-ID correlation (hard to trace a request across service → handler → repo)
- No structured JSON logging (harder to parse in log aggregators)
- `exc_info=True` in `log_error` — good for debugging, but in production this can leak stack traces to log sinks

### 9.2 Error Handling — Score: 8/10

- `custom_exception_handler` normalizes all errors into a consistent `{error, detail, message, error_code}` format ✅
- `PlanPalException` hierarchy provides typed, translatable error codes ✅
- Cache operations fail gracefully (log + return None) ✅

**Gaps:**
- Several views catch `Exception` broadly and return `str(e)`:
  ```python
  except Exception as e:
      return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
  ```
  This leaks internal error details to the client.

### 9.3 Missing Operational Capabilities

| Capability | Status |
|------------|--------|
| Health check endpoint | ❌ Missing |
| Readiness probe (DB + Redis) | ❌ Missing |
| Request-ID middleware | ❌ Missing |
| Prometheus/StatsD metrics | ❌ Missing |
| Distributed tracing (OpenTelemetry) | ❌ Missing |
| Circuit breaker for external services (FCM, Cloudinary) | ❌ Missing |

---

## 10. Security & Data Safety

### 10.1 Critical Security Issues

**S1: `DEBUG = True` — hardcoded**

```python
# settings.py — line 37
DEBUG = True
```

Not conditional on environment. In production (Fly.io), this exposes:
- Full stack traces with source code
- SQL queries in error pages
- Django debug toolbar (if installed)
- Detailed 500 error pages

**Fix:** `DEBUG = os.getenv('DEBUG', 'False').lower() == 'true'`

**S2: `ALLOWED_HOSTS = ['*']`**

Wildcard at end of list overrides all specific entries. Makes the application vulnerable to Host header injection attacks.

**S3: `CORS_ALLOW_ALL_ORIGINS = True`**

```python
CORS_ALLOWED_ORIGINS = ["http://localhost:3000", ...]  # ← ignored
CORS_ALLOW_ALL_ORIGINS = True                           # ← overrides above
CORS_ALLOW_CREDENTIALS = True                           # ← combined with allow_all = dangerous
```

`Allow all origins + Allow credentials` means any website can make authenticated cross-origin requests.

**S4: No API rate limiting**

```python
REST_FRAMEWORK = {
    # No DEFAULT_THROTTLE_CLASSES
    # No DEFAULT_THROTTLE_RATES
}
```

No DRF throttling configured. All endpoints are unprotected against brute force:
- Login endpoint: no rate limit on failed attempts
- Friend request: no rate limit on spam
- Message sending: no rate limit on flood

**S5: `SECRET_KEY` fallback**

```python
SECRET_KEY = os.getenv('SECRET_KEY', 'django-insecure-fallback-key-for-development')
```

If `SECRET_KEY` is not set in production, the app runs with a publicly known key. This compromises:
- Session integrity
- CSRF tokens
- Password reset tokens
- Signed cookies

### 10.2 Data Safety

| Aspect | Status |
|--------|--------|
| OAuth2 token rotation | ✅ `ROTATE_REFRESH_TOKEN = True` |
| Access token TTL | ✅ 1 hour |
| Refresh token TTL | ✅ 1 week |
| Password validators | ✅ 4 validators configured |
| SSL for DB | ✅ `ssl_mode: REQUIRED` for production |
| Soft delete for messages | ✅ `is_deleted` flag |
| Optimistic locking | ✅ `version` field on `PlanActivity` |
| Atomic operations | ✅ `transaction.atomic()` in repositories |
| Transaction-deferred events | ✅ `on_commit()` in `ChannelsDomainEventPublisher` |

---

## Refactoring Roadmap

### Phase 1: Security Hardening (Immediate — 1-2 days)

1. **Environment-conditional DEBUG:**
   ```python
   DEBUG = os.getenv('DJANGO_DEBUG', 'False').lower() == 'true'
   ```

2. **Lock down ALLOWED_HOSTS and CORS:**
   ```python
   ALLOWED_HOSTS = os.getenv('ALLOWED_HOSTS', 'localhost').split(',')
   CORS_ALLOW_ALL_ORIGINS = False  # Remove this line
   ```

3. **Add DRF throttling:**
   ```python
   REST_FRAMEWORK = {
       'DEFAULT_THROTTLE_CLASSES': [
           'rest_framework.throttling.AnonRateThrottle',
           'rest_framework.throttling.UserRateThrottle',
       ],
       'DEFAULT_THROTTLE_RATES': {
           'anon': '20/min',
           'user': '60/min',
       }
   }
   ```

4. **Remove `firebase_service_account.json` from repo**, use environment variable or secret manager.

5. **Fail-closed on missing SECRET_KEY:**
   ```python
   SECRET_KEY = os.environ['SECRET_KEY']  # Crash if not set
   ```

### Phase 2: Dependency Rule Cleanup (3-5 days)

1. Create `shared/domain_exceptions.py` with pure Python exception hierarchy
2. Migrate all handlers to use domain exceptions instead of DRF-based ones
3. Update `custom_exception_handler` to translate domain exceptions to HTTP responses
4. Move `RealtimeEvent` dependency on `django.utils.timezone` to `datetime.datetime.now(timezone.utc)`
5. Extract `PlanService.start_trip()/complete_trip()` logic into proper handlers

### Phase 3: Code Quality (2-3 days)

1. Remove dead code in `GroupViewSet.created_by_me` and `recent_messages`
2. Merge `EnhancedPlanViewSet` / `EnhancedGroupViewSet` into parent viewsets
3. Eliminate validation duplication — serializers should call domain validation functions
4. Consolidate duplicated helper methods (`_get_group_initials`, `_get_duration_display`)
5. Make auth commands extend `BaseCommand` for consistency
6. Fix `GroupCreateSerializer.create()` to batch-fetch users

### Phase 4: Performance & Scalability (3-5 days)

1. Move business logic out of `Plan.save()` and `Group.save()` into handlers
2. Add missing indexes (Friendship, ChatMessage, MessageReadStatus)
3. Replace `unread_messages_count` with denormalized counter
4. Use Redis `LPUSH`/`LTRIM` for offline event cache instead of get/modify/set
5. Switch to database-backed scheduling (`django-celery-beat`) for long-horizon plan ETAs
6. Add health check endpoint (`/health/` — DB + Redis probe)

### Phase 5: Observability (2-3 days)

1. Add request-ID middleware (generate UUID, thread-local, attach to all log records)
2. Switch to structured JSON logging for production
3. Set production log level to `WARNING` (not `DEBUG`)
4. Add `/health/live` and `/health/ready` endpoints
5. Catch and mask generic exceptions in views (don't return `str(e)`)

---

## Final Architecture Recommendation

The PlanPal backend demonstrates a **solid understanding of Clean Architecture principles** that is rare in Django projects. The domain purity, repository abstraction, handler pattern, and factory composition roots form a genuinely well-structured system.

**The architecture is ready for production after addressing Phase 1 (security) and Phase 2 (dependency rule).** The remaining phases are optimizations that matter at scale but aren't blockers.

### Architecture Scorecard

| Dimension | Score | Notes |
|-----------|-------|-------|
| Clean Architecture Compliance | 8/10 | Domain layers are exemplary; exception hierarchy leaks DRF |
| Dependency Rule Adherence | 7.5/10 | One systematic violation (exceptions) + minor event import |
| DB & Query Performance | 8/10 | Good indexes, some N+1 risks in model save/str methods |
| Caching Architecture | 8.5/10 | Stampede prevention + versioned keys; missing membership caching |
| Async Processing | 9/10 | Best-in-class Celery setup with queues, retries, observability |
| Scalability | 6.5/10 | Single Redis, no connection pooling, O(N) group creation |
| Code Quality | 7/10 | Dead code, duplication, inconsistent error languages |
| Observability | 6/10 | Basic logging only; no metrics, tracing, or health checks |
| Security | 5/10 | Critical: DEBUG=True, CORS open, no rate limiting |

**Overall: 7.3/10** — Strong bones, needs hardening before serving real users at scale.
