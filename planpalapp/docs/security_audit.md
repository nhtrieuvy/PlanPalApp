# PlanPal Security Audit Report

**Date**: 2025  
**Scope**: RBAC, Permissions, OAuth, Dead Code, Hardening  
**Overall Score**: 5.8 / 10 — Multiple critical & high-severity issues found

---

## 1. RBAC Architecture Review

### Current Model
PlanPal uses DRF's `BasePermission` classes, composed per-ViewSet or per-action:

| Context | ViewSet | Permission Stack |
|---------|---------|-----------------|
| Plans | `PlanViewSet` | `[IsAuthenticated, PlanPermission]` |
| Plans | `PlanActivityViewSet` | `[IsAuthenticated, PlanActivityPermission]` |
| Groups | `GroupViewSet` | `[IsAuthenticated, GroupPermission]` |
| Chat | `ChatMessageViewSet` | `[IsAuthenticated, ChatMessagePermission]` |
| Chat | `ConversationViewSet` | `[IsAuthenticated]` — **no object-level perm** |
| Auth | `UserViewSet` | Dynamic via `get_permissions()` |
| Notifications | `SendNotificationView` | `[IsAuthenticated]` |
| Locations | All views | `[IsAuthenticated]` |

### Findings

- **No global `DEFAULT_PERMISSION_CLASSES`** — settings.py omits this, relying on each ViewSet to set its own. If any ViewSet forgets, endpoints default to unauthenticated access.
- **4 independent permission modules** with overlapping semantics and no shared base.
- **22 permission classes** across 4 files — significant redundancy.
- **No role enum** — roles are string literals ("admin", "member") scattered across code.

---

## 2. Plan Permission Model

### CRITICAL: `CanModifyPlan` allows ANY group member to modify
**File**: `plans/presentation/permissions.py:124-136`  
**Severity**: CRITICAL

```python
class CanModifyPlan(BasePermission):
    def has_object_permission(self, request, view, obj):
        plan = obj
        user = request.user
        if plan.creator == user:
            return True
        if plan.plan_type == 'group' and plan.group:
            if plan.group.admin == user:
                return True
            return plan.group.is_member(user)  # ← ANY member can modify!
        return False
```

This allows any group member to add/update/delete activities on any plan in the group, even plans they didn't create. The intent should be: only plan creator or group admin can modify.

### CRITICAL: `CanJoinPlan` allows joining private groups
**File**: `plans/presentation/permissions.py:100-117`  
**Severity**: CRITICAL

```python
class CanJoinPlan(BasePermission):
    def has_object_permission(self, request, view, obj):
        # ...
        if plan.plan_type == 'group' and plan.group:
            if plan.group.members.filter(id=user.id).exists():
                return False
            if getattr(plan.group, 'is_public', True):  # defaults True!
                return True
            return True  # ← ALWAYS returns True regardless of group privacy!
```

Both branches return `True`. A user who isn't a member of a private group can join any plan associated with it.

### HIGH: `PlanActivityViewSet.get_queryset()` excludes personal plans
**File**: `plans/presentation/views.py:369-371`

```python
def get_queryset(self):
    return PlanActivity.objects.filter(
        plan__group__members=self.request.user  # ← personal plans have no group!
    )
```

Activities from personal plans are invisible to their own creator.

### HIGH: Duplicate endpoints `add_activity` and `create_activity`
**File**: `plans/presentation/views.py`

Both `add_activity` (line 157) and `create_activity` (line 175) call `PlanService.add_activity_to_plan` with identical logic. This doubles the attack surface.

---

## 3. Group Permission Model

### HIGH: `GroupPermission._can_view_group` defaults `is_public` to True
**File**: `groups/presentation/permissions.py:21-23`

```python
def _can_view_group(self, user, group):
    if getattr(group, 'is_public', True):  # defaults True if field missing
        return True
```

If the `Group` model lacks an `is_public` field (which it does — it's not defined), `getattr` returns `True`, making every group publicly viewable.

### MEDIUM: `GroupMembershipPermission._can_join_group` same default-True pattern
**File**: `groups/presentation/permissions.py:46-49`

Same `getattr(group, 'is_public', True)` problem — private groups can be joined.

---

## 4. OAuth Security Audit

### Settings Analysis
- **`GRANT_PASSWORD`** is used — Resource Owner Password Credentials grant. Acceptable for first-party mobile apps but should be noted.
- **Token rotation**: `ROTATE_REFRESH_TOKEN = True` ✅
- **Token TTLs**: Access = 1h, Refresh = 1 week — reasonable.
- **WebSocket auth**: Token passed via query string (`?token=xxx`) — visible in logs. Acceptable tradeoff for WebSocket.

### HIGH: No token expiry check on WebSocket disconnect
The `TokenAuthMiddleware` calls `access_token.is_valid()` on connect but there's no periodic revalidation. A revoked token continues working for the WebSocket session.

### MEDIUM: OAuth endpoints at `/o/` are publicly accessible
Standard oauth2_provider behavior, but combined with `GRANT_PASSWORD`, an attacker who obtains `client_id` can brute-force credentials.

---

## 5. Permission Enforcement Strategy

### Missing `DEFAULT_PERMISSION_CLASSES`
`REST_FRAMEWORK` in settings has no `DEFAULT_PERMISSION_CLASSES`. Any new ViewSet without explicit `permission_classes` will be OPEN by default.

### `ConversationViewSet` missing object-level permissions
**File**: `chat/presentation/views.py:210`

```python
class ConversationViewSet(...):
    permission_classes = [IsAuthenticated]  # No object-level permission!
```

The `send_message` and `messages` actions do inline `_can_user_access_conversation` checks, but `mark_read` and `create_direct` don't have this line.

### `EnhancedPlanViewSet.add_activity_with_place` missing explicit permission
Inherits `PlanPermission` from parent `PlanViewSet`, but `PlanPermission.has_object_permission` only checks `can_edit_plan` for non-safe methods — it does NOT verify modification rights specifically. Should use `CanModifyPlan` (once fixed).

---

## 6. Dead Code Detection

### Unused Permission Classes (NEVER referenced in any ViewSet)
| Class | File | Status |
|-------|------|--------|
| `GroupMembershipPermission` | `groups/presentation/permissions.py` | **DEAD** — defined but never imported anywhere |
| `IsOwnerOrGroupAdmin` | `plans/presentation/permissions.py` | **DEAD** — defined but never imported anywhere |
| `IsOwnerOrReadOnly` | `plans/presentation/permissions.py` | **DEAD** — defined but never imported anywhere |
| `IsFriend` | `auth/presentation/permissions.py` | **DEAD** — never imported in views |
| `IsConversationParticipant` | `chat/presentation/permissions.py` | **DEAD** — never imported in views |

### Imported But Never Used
| Symbol | File | Status |
|--------|------|--------|
| `CanNotTargetSelf` | `auth/presentation/views.py:25` | Imported but never used in `get_permissions()` or `permission_classes` |
| `ConversationPermission` | `chat/presentation/views.py:13` | Imported but `ConversationViewSet` uses only `[IsAuthenticated]` |

### Bug: `chat/presentation/views.py:173` — NameError
```python
serializer = self.get_serializer(queryset, many=True)
return Response({
    'messages': serializer.data,
    'count': len(messages),  # ← 'messages' is not defined, should be serializer.data
    'query': query
})
```

---

## 7. Dead File Detection

No completely dead files found. The `planpals/models.py` re-export façade is actively used (20+ imports). All infrastructure modules are referenced.

---

## 8. Security Hardening

### CRITICAL: `DEBUG = True` hardcoded
**File**: `settings.py:37`
```python
DEBUG = True
```
Must be environment-driven.

### CRITICAL: `CORS_ALLOW_ALL_ORIGINS = True`
**File**: `settings.py:251`

Allows any origin to make authenticated cross-origin requests. Combined with `CORS_ALLOW_CREDENTIALS = True`, this is a credential-theft vector.

### CRITICAL: `ALLOWED_HOSTS = ['*']`
**File**: `settings.py:39`

Contains `'*'` wildcard — allows HTTP Host header attacks.

### HIGH: Swagger/ReDoc publicly accessible
**File**: `planpalapp/urls.py:34-42`

```python
path('swagger/', schema_view.with_ui('swagger', cache_timeout=0),
     name='schema-swagger-ui'),  # permission_classes=(AllowAny,)
```

API documentation exposes all endpoints, parameters, and response schemas to unauthenticated users.

### HIGH: `SendNotificationView` — any authenticated user can push to anyone
**File**: `notifications/presentation/views.py`

Any authenticated user can send push notifications to any other user by specifying their `recipient_id`. No check that the sender has a relationship with the recipient.

### MEDIUM: Insecure `SECRET_KEY` fallback
**File**: `settings.py:35`
```python
SECRET_KEY = os.getenv('SECRET_KEY', 'django-insecure-fallback-key-for-development')
```

If the env var is unset, the app runs with a known secret key.

### MEDIUM: `ChatMessageSerializer` accepts `group_id` from request body
**File**: `chat/presentation/views.py:47`

The `create` method takes `group_id` from `request.data` — potential IDOR if not validated (it is validated via `Group.objects.get` + membership check, but the pattern is fragile).

---

## 9. Remediation Plan

| # | Fix | Severity | Files |
|---|-----|----------|-------|
| 1 | Fix `CanModifyPlan` — remove `is_member` fallback | CRITICAL | `plans/presentation/permissions.py` |
| 2 | Fix `CanJoinPlan` — enforce group privacy | CRITICAL | `plans/presentation/permissions.py` |
| 3 | Fix `GroupPermission._can_view_group` — don't default `is_public` to True | HIGH | `groups/presentation/permissions.py` |
| 4 | Gate Swagger/ReDoc behind `DEBUG` | HIGH | `planpalapp/urls.py` |
| 5 | Environment-driven `DEBUG`, remove `'*'` from `ALLOWED_HOSTS` | CRITICAL | `settings.py` |
| 6 | Disable `CORS_ALLOW_ALL_ORIGINS` in production | CRITICAL | `settings.py` |
| 7 | Add `DEFAULT_PERMISSION_CLASSES` to `REST_FRAMEWORK` | HIGH | `settings.py` |
| 8 | Remove 5 dead permission classes | LOW | 3 permission files |
| 9 | Remove unused imports (`CanNotTargetSelf`, `ConversationPermission`) | LOW | 2 view files |
| 10 | Remove duplicate `add_activity` endpoint | MEDIUM | `plans/presentation/views.py` |
| 11 | Fix `PlanActivityViewSet.get_queryset()` to include personal plans | HIGH | `plans/presentation/views.py` |
| 12 | Fix `SendNotificationView` — add authorization check | HIGH | `notifications/presentation/views.py` |
| 13 | Fix chat search NameError (`messages` → `serializer.data`) | HIGH | `chat/presentation/views.py` |

---

## 10. Overall Assessment

| Category | Score | Notes |
|----------|-------|-------|
| RBAC Design | 5/10 | Redundant classes, no role enum, no default perms |
| Plan Permissions | 3/10 | Two CRITICAL bypasses |
| Group Permissions | 6/10 | Default-True `is_public` assumption |
| OAuth | 7/10 | Solid config, minor WebSocket gap |
| Enforcement Strategy | 4/10 | Inconsistent, missing object-level on conversations |
| Dead Code | 7/10 | 5 dead classes, 2 unused imports |
| Hardening | 3/10 | DEBUG=True, CORS=*, Swagger public |
| **Overall** | **5.8/10** | Multiple critical issues need immediate fixing |
