# PlanPal Backend — Clean Architecture Guide

## Mục lục
1. [Giải thích kiến trúc](#1-giải-thích-kiến-trúc)
2. [Cấu trúc thư mục](#2-cấu-trúc-thư-mục)
3. [Dependency Diagram](#3-dependency-diagram)
4. [Ví dụ code từng layer](#4-ví-dụ-code-từng-layer)
5. [Before → After](#5-before--after)
6. [Lỗi thường gặp](#6-lỗi-thường-gặp)
7. [Hướng dẫn migration từng bước](#7-hướng-dẫn-migration-từng-bước)

---

## 1. Giải thích kiến trúc

PlanPal backend áp dụng **Clean Architecture** (Robert C. Martin) theo 4 layer đồng tâm, kết hợp với **Bounded Context** từ Domain-Driven Design.

### Nguyên tắc cốt lõi: Dependency Rule

> **Mã nguồn chỉ được phụ thuộc hướng vào trong (inward).**
> Layer bên trong KHÔNG BAO GIỜ biết về layer bên ngoài.

```
┌─────────────────────────────────────────────────────────┐
│                    PRESENTATION                         │
│   (DRF ViewSets, Serializers, URL routing)              │
│  ┌───────────────────────────────────────────────────┐  │
│  │               APPLICATION                         │  │
│  │  (Services, Commands, Handlers, Factories)        │  │
│  │  ┌─────────────────────────────────────────────┐  │  │
│  │  │            INFRASTRUCTURE                   │  │  │
│  │  │  (Django ORM Models, Repositories impl,     │  │  │
│  │  │   Signals, Consumers, External services)    │  │  │
│  │  │  ┌───────────────────────────────────────┐  │  │  │
│  │  │  │              DOMAIN                   │  │  │  │
│  │  │  │  Pure Python: Enums, Constants,       │  │  │  │
│  │  │  │  Validation, Repository ABCs,         │  │  │  │
│  │  │  │  Domain Events                        │  │  │  │
│  │  │  └───────────────────────────────────────┘  │  │  │
│  │  └─────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Vai trò từng layer

| Layer | Chứa | Được import bởi | Phụ thuộc |
|-------|-------|------------------|-----------|
| **Domain** | Entities (enums, constants), Repository ABCs, Domain Events | Tất cả layers | Không gì (Pure Python) |
| **Infrastructure** | Django ORM Models, Repository implementations, Signals, WebSocket Consumers | Application, Presentation | Domain |
| **Application** | Commands, Handlers, Services, Factories | Presentation | Domain, Infrastructure (qua DI) |
| **Presentation** | DRF ViewSets, Serializers, Permissions, URL configs | Không ai | Application, Infrastructure |

### 4 Bounded Contexts

| Context | Trách nhiệm |
|---------|-------------|
| `auth` | User, Friendship, FriendshipRejection, đăng nhập/đăng ký |
| `plans` | Plan, PlanActivity, lập kế hoạch du lịch |
| `groups` | Group, GroupMembership, quản lý nhóm |
| `chat` | Conversation, ChatMessage, MessageReadStatus, tin nhắn |

---

## 2. Cấu trúc thư mục

```
planpals/                          # Django app
├── models.py                      # Facade: re-export từ infrastructure
├── admin.py                       # Django Admin
├── apps.py                        # AppConfig + domain event registration
├── urls.py                        # Root URL routing
├── routing.py                     # WebSocket routing
├── tasks.py                       # Celery tasks
│
├── shared/                        # Cross-cutting concerns
│   ├── base_models.py             # BaseModel (Django abstract, UUID PK)
│   ├── interfaces.py              # BaseRepository, BaseCommand, BaseCommandHandler,
│   │                              #   DomainEvent, DomainEventPublisher, UnitOfWork
│   └── infrastructure.py          # DjangoUnitOfWork, ChannelsDomainEventPublisher
│
├── auth/                          # ═══ Bounded Context: Auth ═══
│   ├── domain/
│   │   ├── entities.py            # ✅ Pure Python: FriendshipStatus enum, cooldown constants
│   │   ├── repositories.py        # ✅ Pure Python: UserRepository ABC, FriendshipRepository ABC
│   │   ├── events.py              # ✅ Pure Python: FriendRequestSent, UserOnline, etc.
│   │   └── models.py              # ⛔ DEPRECATED (stub) — ORM moved to infrastructure
│   ├── application/
│   │   ├── commands.py            # SendFriendRequestCommand, AcceptFriendRequestCommand, etc.
│   │   ├── handlers.py            # Handler per command, imports domain entities not ORM
│   │   ├── services.py            # UserService (delegates to handlers)
│   │   └── factories.py           # HandlerFactory: wires repos → handlers
│   ├── infrastructure/
│   │   ├── models.py              # User, Friendship, FriendshipRejection (Django ORM)
│   │   ├── repositories.py        # DjangoUserRepository, DjangoFriendshipRepository
│   │   ├── signals.py             # Post-save signals
│   │   └── consumers.py           # WebSocket consumers
│   └── presentation/
│       ├── views.py               # DRF ViewSets
│       ├── serializers.py         # DRF Serializers
│       ├── permissions.py         # DRF Permissions
│       └── urls.py                # URL patterns
│
├── plans/                         # ═══ Bounded Context: Plans ═══
│   ├── domain/
│   │   ├── entities.py            # PlanType, PlanStatus, ActivityType enums + validation fns
│   │   ├── repositories.py        # PlanRepository ABC, PlanActivityRepository ABC
│   │   ├── events.py              # PlanCreated, PlanUpdated, etc.
│   │   └── models.py              # ⛔ DEPRECATED
│   ├── application/
│   │   ├── commands.py
│   │   ├── handlers.py
│   │   ├── services.py
│   │   ├── factories.py
│   │   └── tasks.py               # Celery tasks (auto-update status)
│   ├── infrastructure/
│   │   ├── models.py              # Plan, PlanActivity (Django ORM)
│   │   ├── repositories.py
│   │   ├── signals.py
│   │   └── consumers.py
│   └── presentation/
│       ├── views.py
│       ├── serializers.py
│       └── urls.py
│
├── groups/                        # ═══ Bounded Context: Groups ═══
│   └── (same 4-layer structure)
│
└── chat/                          # ═══ Bounded Context: Chat ═══
    └── (same 4-layer structure)
```

---

## 3. Dependency Diagram

```
                    ┌─────────────────┐
                    │   presentation/  │
                    │  views.py        │──────────────────────┐
                    │  serializers.py  │                      │
                    │  permissions.py  │                      │
                    └────────┬────────┘                      │
                             │ imports                       │ imports
                             ▼                               ▼
                    ┌─────────────────┐            ┌──────────────────┐
                    │  application/    │            │  infrastructure/  │
                    │  services.py     │───────────▶│  models.py (ORM) │
                    │  handlers.py     │  imports   │  repositories.py │
                    │  commands.py     │            │  signals.py      │
                    │  factories.py    │            │  consumers.py    │
                    └────────┬────────┘            └────────┬─────────┘
                             │ imports                      │ imports
                             ▼                              ▼
                    ┌──────────────────────────────────────────┐
                    │              domain/                      │
                    │  entities.py     (Pure Python enums)      │
                    │  repositories.py (ABCs — interfaces)      │
                    │  events.py       (Dataclass events)       │
                    │                                          │
                    │  ⚠️  NO Django, NO ORM, NO DRF imports   │
                    └──────────────────────────────────────────┘

  Allowed dependency directions:
    presentation → application, infrastructure
    application  → domain (entities, repos, events)
    application  → infrastructure (via DI / factories, NOT direct ORM)
    infrastructure → domain (implements ABCs)
    domain       → NOTHING (pure Python)

  ❌ FORBIDDEN:
    domain → infrastructure
    domain → application
    domain → presentation
    infrastructure → presentation
    infrastructure → application (except via events)
```

### Cross-context dependencies

```
  auth ←──── plans     (Plan.creator FK → User)
  auth ←──── groups    (GroupMembership.user FK → User)
  auth ←──── chat      (Conversation.user_a/user_b FK → User)
  groups ←── plans     (Plan.group FK → Group)
  groups ←── chat      (Conversation.group FK → Group)
```

Các cross-context reference dùng **string FK** (`'planpals.User'`) hoặc lazy import trong infrastructure layer.

---

## 4. Ví dụ code từng layer

### Domain Layer — `auth/domain/entities.py`

```python
"""Pure Python — KHÔNG import Django"""
from enum import Enum
from datetime import datetime, timedelta

class FriendshipStatus(str, Enum):
    PENDING = 'pending'
    ACCEPTED = 'accepted'
    REJECTED = 'rejected'
    BLOCKED = 'blocked'

REJECTION_COOLDOWN_HOURS = 24
MAX_REJECTION_COUNT = 3
EXTENDED_COOLDOWN_DAYS = 7

def can_resend_after_rejection(
    rejection_count: int,
    last_rejection_time: datetime | None,
    now: datetime,
) -> tuple[bool, str]:
    if last_rejection_time is None:
        return True, ""
    elapsed = now - last_rejection_time
    if rejection_count >= MAX_REJECTION_COUNT:
        cooldown = timedelta(days=EXTENDED_COOLDOWN_DAYS)
        msg = f"Must wait {EXTENDED_COOLDOWN_DAYS} days"
    else:
        cooldown = timedelta(hours=REJECTION_COOLDOWN_HOURS)
        msg = f"Must wait {REJECTION_COOLDOWN_HOURS} hours"
    if elapsed < cooldown:
        return False, f"Cannot resend. {msg}. Remaining: {cooldown - elapsed}"
    return True, ""
```

### Domain Layer — `auth/domain/repositories.py`

```python
"""Repository interface — chỉ dùng ABC + typing"""
from abc import ABC, abstractmethod
from typing import Optional, Any
from uuid import UUID

class FriendshipRepository(ABC):
    @abstractmethod
    def get_friendship(self, user1_id: UUID, user2_id: UUID) -> Optional[Any]: ...

    @abstractmethod
    def create_friendship(self, user1_id: UUID, user2_id: UUID, initiator_id: UUID) -> Any: ...

    @abstractmethod
    def update_status(self, friendship_id: UUID, new_status: str) -> Any: ...

    @abstractmethod
    def create_rejection(self, friendship_id: UUID, rejected_by_id: UUID) -> Any: ...

    @abstractmethod
    def reopen_as_pending(self, friendship_id: UUID, initiator_id: UUID) -> Any: ...
```

### Infrastructure Layer — `auth/infrastructure/models.py`

```python
"""Django ORM Models — infrastructure concern"""
from django.db import models
from django.contrib.auth.models import AbstractUser
from planpals.shared.base_models import BaseModel
from planpals.auth.domain.entities import FriendshipStatus

class User(AbstractUser, BaseModel):
    phone_number = models.CharField(max_length=17, blank=True)
    avatar = CloudinaryField('image', blank=True, null=True)
    # ... other fields
    class Meta:
        app_label = 'planpals'
        db_table = 'planpal_users'
```

### Infrastructure Layer — `auth/infrastructure/repositories.py`

```python
"""Implements domain repository ABCs using Django ORM"""
from planpals.auth.domain.repositories import FriendshipRepository
from planpals.auth.infrastructure.models import Friendship, FriendshipRejection

class DjangoFriendshipRepository(FriendshipRepository):
    def get_friendship(self, user1_id, user2_id):
        return Friendship.objects.between_users(user1_id, user2_id).first()

    def create_rejection(self, friendship_id, rejected_by_id):
        friendship = Friendship.objects.get(id=friendship_id)
        rejection = FriendshipRejection(friendship=friendship, rejected_by_id=rejected_by_id)
        rejection.full_clean()
        rejection.save()
        return rejection
```

### Application Layer — `auth/application/handlers.py`

```python
"""Command handlers — import domain entities, NOT ORM models"""
from planpals.auth.domain.entities import FriendshipStatus, can_resend_after_rejection
from planpals.auth.domain.repositories import FriendshipRepository

class RejectFriendRequestHandler(BaseCommandHandler):
    def __init__(self, friendship_repo: FriendshipRepository):
        self.friendship_repo = friendship_repo  # Interface, not concrete class

    def handle(self, command):
        friendship = self.friendship_repo.get_friendship(...)
        if friendship.status != FriendshipStatus.PENDING:    # ← domain enum
            return False, "Not pending"
        self.friendship_repo.create_rejection(...)            # ← repo method
        self.friendship_repo.update_status(..., FriendshipStatus.REJECTED)
        return True, "Rejected"
```

### Application Layer — `auth/application/factories.py`

```python
"""Dependency Injection — wires infrastructure to application"""
from planpals.auth.infrastructure.repositories import DjangoUserRepository, DjangoFriendshipRepository
from planpals.shared.infrastructure import ChannelsDomainEventPublisher

class AuthHandlerFactory:
    @staticmethod
    def send_friend_request_handler():
        return SendFriendRequestHandler(
            user_repo=DjangoUserRepository(),
            friendship_repo=DjangoFriendshipRepository(),
            event_publisher=ChannelsDomainEventPublisher(),
        )
```

### Presentation Layer — `auth/presentation/views.py`

```python
"""DRF ViewSets — imports from infrastructure (models) and application (services)"""
from rest_framework import viewsets
from planpals.auth.infrastructure.models import User, Friendship
from planpals.auth.application.services import UserService

class FriendshipViewSet(viewsets.ViewSet):
    def create(self, request):
        service = UserService()
        success, msg = service.send_friend_request(request.user.id, target_id)
        # ...
```

---

## 5. Before → After

### Before (Vi phạm Dependency Rule)

```
auth/domain/models.py              ← Django ORM models tại domain layer!
├── from django.db import models    ← ❌ Django dependency trong domain
├── from django.contrib.auth.models import AbstractUser
├── from cloudinary.models import CloudinaryField
├── class User(AbstractUser):       ← ❌ ORM model tại innermost layer
├── class Friendship(BaseModel):    ← ❌ BaseModel kế thừa từ Django
└── class FriendshipRejection:

auth/application/handlers.py
├── from planpals.auth.domain.models import Friendship  ← ❌ Lazy import ORM
├── friendship.save(update_fields=[...])                ← ❌ Direct ORM save
└── FriendshipRejection(...).save()                     ← ❌ Direct ORM create
```

### After (Clean Architecture)

```
auth/domain/entities.py             ← ✅ Pure Python
├── from enum import Enum            ← ✅ Standard library only
├── class FriendshipStatus(str, Enum)
├── REJECTION_COOLDOWN_HOURS = 24
└── def can_resend_after_rejection()

auth/domain/repositories.py         ← ✅ Pure Python ABCs
├── from abc import ABC
└── class FriendshipRepository(ABC)

auth/infrastructure/models.py       ← ✅ ORM models tại infrastructure
├── from django.db import models     ← ✅ Django chỉ ở infrastructure
├── class User(AbstractUser, BaseModel)
├── class Friendship(BaseModel)
└── class FriendshipRejection(BaseModel)

auth/application/handlers.py        ← ✅ Clean imports
├── from planpals.auth.domain.entities import FriendshipStatus  ← ✅
├── self.friendship_repo.reopen_as_pending(...)                 ← ✅ Via repo
└── self.friendship_repo.create_rejection(...)                  ← ✅ Via repo
```

---

## 6. Lỗi thường gặp

### ❌ 1. Import ORM model trong domain layer

```python
# domain/entities.py
from django.db import models  # ❌ TUYỆT ĐỐI KHÔNG
```

**Fix:** Domain layer chỉ dùng Python standard library (`enum`, `dataclasses`, `typing`, `abc`, `datetime`, `uuid`).

### ❌ 2. Import domain.models thay vì infrastructure.models

```python
# application/services.py
from planpals.auth.domain.models import User  # ❌ domain.models đã deprecated
```

**Fix:**
```python
from planpals.auth.infrastructure.models import User  # ✅
# hoặc
from planpals.models import User  # ✅ qua facade
```

### ❌ 3. Handler trực tiếp gọi .save() trên ORM model

```python
# application/handlers.py
friendship.status = 'accepted'
friendship.save(update_fields=['status'])  # ❌ Direct ORM operation
```

**Fix:**
```python
self.friendship_repo.update_status(friendship.id, FriendshipStatus.ACCEPTED)  # ✅
```

### ❌ 4. Handler tạo ORM object trực tiếp

```python
# application/handlers.py
rejection = FriendshipRejection(friendship=f, rejected_by_id=uid)
rejection.save()  # ❌
```

**Fix:**
```python
self.friendship_repo.create_rejection(friendship.id, uid)  # ✅
```

### ❌ 5. Dùng magic string thay vì domain enum

```python
if friendship.status == 'accepted':  # ❌ Magic string
```

**Fix:**
```python
from planpals.auth.domain.entities import FriendshipStatus
if friendship.status == FriendshipStatus.ACCEPTED:  # ✅
```

### ❌ 6. Cross-context import domain layer trực tiếp

```python
# chat/infrastructure/models.py
from planpals.auth.domain.entities import FriendshipStatus  # ⚠️ OK (pure Python)
from planpals.auth.infrastructure.models import User        # ⚠️ Infrastructure OK
from planpals.auth.domain.models import User                # ❌ Deprecated
```

### ❌ 7. Business logic trong Presentation layer

```python
# presentation/views.py
if Friendship.objects.filter(user_a=user, status='accepted').count() > 100:
    return Response("Too many friends")  # ❌ Business logic in view
```

**Fix:** Đưa logic vào Application layer (service/handler).

---

## 7. Hướng dẫn migration từng bước

Dưới đây là quy trình đã thực hiện để chuyển PlanPal sang Clean Architecture:

### Bước 1: Tạo domain entities (Pure Python)

Cho mỗi bounded context, tạo `domain/entities.py` chứa:
- **Enums** cho các trạng thái, loại (thay thế magic strings trong ORM models)
- **Constants** cho business rules (cooldown hours, max counts, etc.)
- **Pure validation functions** (không phụ thuộc ORM)

```bash
# Các file đã tạo:
planpals/auth/domain/entities.py      # FriendshipStatus, cooldown constants
planpals/plans/domain/entities.py     # PlanType, PlanStatus, ActivityType + validation
planpals/groups/domain/entities.py    # MembershipRole
planpals/chat/domain/entities.py      # ConversationType, MessageType
```

### Bước 2: Tạo infrastructure/models.py

Copy toàn bộ ORM model code từ `domain/models.py` sang `infrastructure/models.py`.

```bash
# Các file đã tạo:
planpals/auth/infrastructure/models.py     # User, Friendship, FriendshipRejection
planpals/plans/infrastructure/models.py    # Plan, PlanActivity
planpals/groups/infrastructure/models.py   # Group, GroupMembership
planpals/chat/infrastructure/models.py     # Conversation, ChatMessage, MessageReadStatus
```

### Bước 3: Thêm repository methods mới

Nếu handlers trực tiếp gọi `.save()` hoặc tạo ORM objects, thêm methods vào repository interface + implementation:

```python
# domain/repositories.py (interface)
class FriendshipRepository(ABC):
    @abstractmethod
    def create_rejection(self, friendship_id: UUID, rejected_by_id: UUID) -> Any: ...
    @abstractmethod
    def reopen_as_pending(self, friendship_id: UUID, initiator_id: UUID) -> Any: ...
    @abstractmethod
    def block_friendship(self, friendship_id: UUID, blocker_id: UUID) -> Any: ...
```

### Bước 4: Cập nhật handlers

Thay thế:
- `from planpals.auth.domain.models import Friendship` → `from planpals.auth.domain.entities import FriendshipStatus`
- `friendship.save()` → `self.friendship_repo.reopen_as_pending()`
- `FriendshipRejection(...).save()` → `self.friendship_repo.create_rejection()`

### Bước 5: Cập nhật tất cả imports

Tìm và thay thế trên toàn codebase:
```
from planpals.{ctx}.domain.models import X
→
from planpals.{ctx}.infrastructure.models import X
```

Các file cần cập nhật:
- `application/services.py` (4 contexts)
- `infrastructure/repositories.py` (4 contexts)
- `presentation/views.py`, `serializers.py`, `permissions.py`
- `infrastructure/signals.py`, `consumers.py`
- `application/tasks.py`, `handlers.py` (lazy imports)
- Root `planpals/models.py` (facade)

### Bước 6: Dọn dẹp domain/models.py

Thay nội dung `domain/models.py` bằng deprecation comment:

```python
"""
DEPRECATED: ORM models have been moved to infrastructure/models.py
"""
```

### Bước 7: Verification

```bash
python manage.py check              # No errors
python manage.py makemigrations --check --dry-run  # No changes detected
```

---

## Checklist cho developer

Khi thêm feature mới, kiểm tra:

- [ ] Domain layer (`domain/`) chỉ chứa Pure Python (enum, dataclass, ABC, typing)
- [ ] ORM models nằm trong `infrastructure/models.py`
- [ ] Repository interface (`domain/repositories.py`) là ABC
- [ ] Repository implementation (`infrastructure/repositories.py`) import từ `infrastructure.models`
- [ ] Handlers import enums/constants từ `domain/entities.py`, không từ ORM models
- [ ] Handlers không gọi `.save()`, `.delete()`, `.objects.filter()` trực tiếp
- [ ] ViewSets import models từ `infrastructure.models` hoặc `planpals.models`
- [ ] Cross-context dùng string FK (`'planpals.User'`) hoặc lazy import
