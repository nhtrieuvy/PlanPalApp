# AI System Design - PlanPal

Generated: 2026-04-08  
Scope: Django backend, Flutter frontend, Riverpod state, Channels realtime, Celery async, Audit Log, Notification System, Analytics Dashboard.

This document is optimized for AI agents and senior engineers. It focuses on behavior, dependencies, invariants, contracts, and safe modification points.

---

## 1. System Mental Model

PlanPal is a layered, event-enriched travel planning system.

Core runtime pattern:

```text
User
  -> performs action in Flutter UI
  -> Riverpod notifier/provider calls repository
  -> repository calls REST API or WebSocket
  -> DRF view validates request and delegates to application service
  -> application service/command handler applies business rules
  -> repository persists state
  -> state change emits domain event and/or audit log
  -> side effects run synchronously (cache invalidation, websocket publish)
     or asynchronously (Celery notifications, reminders, analytics aggregation)
  -> response is serialized back to Flutter DTOs
```

High-level system equation:

```text
User -> Actions -> System -> State changes -> Side effects

Examples
- Create plan -> Plan row created -> Audit log -> Notification fan-out -> Scheduled status tasks
- Join group -> Membership row created -> Audit log -> Notify admins
- Send message -> ChatMessage row created -> Conversation updated -> WebSocket fan-out -> Push notification
- Open notification -> Notification marked read -> Audit log NOTIFICATION_OPENED -> Analytics aggregate later
```

Primary state stores:

- MySQL: source of truth for users, groups, plans, activities, friendships, chat, audit logs, notifications, analytics snapshots.
- Redis or local memory cache: short-lived read cache, Celery broker/result backend, Channels backend in deployed environments.
- Channels groups: transient realtime fan-out transport.
- Celery queues: deferred notification, reminder, analytics, cleanup execution.

Primary design principle:

- Request-time endpoints should do transactional state changes and lightweight reads.
- Expensive or fan-out work is delegated to Celery.
- Historical metrics come from pre-aggregated tables, not live scans.

---

## 2. Domain Model Graph

```text
User
 ├── owns -> Plan
 ├── joins -> Group (through GroupMembership)
 ├── sends/receives -> Friendship
 ├── participates in -> Conversation
 ├── sends -> ChatMessage
 ├── receives -> Notification
 ├── owns -> UserDeviceToken
 ├── causes -> AuditLog
 └── contributes to -> DailyMetric (through activity and audit history)

Friendship
 ├── connects -> User A
 ├── connects -> User B
 └── may have -> FriendshipRejection history

Group
 ├── owned by -> admin User
 ├── contains -> GroupMembership
 ├── contains -> member Users
 ├── owns -> Plan (group plans)
 └── owns -> Conversation (group chat)

GroupMembership
 ├── belongs to -> Group
 ├── belongs to -> User
 └── carries -> role (admin/member)

Plan
 ├── belongs to -> creator User
 ├── optionally belongs to -> Group
 ├── contains -> PlanActivity
 ├── referenced by -> AuditLog
 ├── referenced by -> Notification data
 └── contributes to -> DailyMetric

PlanActivity
 └── belongs to -> Plan

Conversation
 ├── direct: links -> user_a, user_b
 ├── group: links -> Group
 └── contains -> ChatMessage

ChatMessage
 ├── belongs to -> Conversation
 ├── optionally replies to -> ChatMessage
 └── has many -> MessageReadStatus

MessageReadStatus
 ├── belongs to -> ChatMessage
 └── belongs to -> User

AuditLog
 ├── belongs to -> nullable User actor
 ├── references -> resource_type/resource_id
 ├── stores -> metadata JSON
 ├── feeds -> Notification fan-out
 └── feeds -> DailyMetric aggregation

Notification
 ├── belongs to -> User
 ├── stores -> type/title/message/data
 ├── may trigger -> push notification
 ├── may emit -> realtime event
 └── contributes to -> DailyMetric (sent count)

UserDeviceToken
 ├── belongs to -> User
 └── enables -> FCM push delivery

DailyMetric
 ├── aggregates -> AuditLog
 ├── aggregates -> Notification open/send counts
 └── powers -> Analytics Dashboard
```

---

## 3. Dependency Graph (Critical)

### 3.1 Backend Layer Rule

```text
Presentation -> Application -> Domain
Infrastructure -> Domain
Infrastructure -> Application (factory wiring only)

Forbidden direction:
Domain -X-> Django, DRF, ORM, Celery, Channels
Application -X-> ORM models directly
Presentation -X-> ORM or business logic directly
```

### 3.2 Actual Backend Module Map

```text
planpals.auth
  presentation: views, serializers, permissions
  application: services, commands, handlers, factories
  domain: entities
  infrastructure: models, repositories, websocket auth

planpals.groups
  presentation: views, serializers, permissions
  application: services, commands, handlers, factories
  domain: repositories, events
  infrastructure: models, repositories, consumers

planpals.plans
  presentation: views, serializers, permissions
  application: services, commands, handlers, factories
  domain: repositories, events
  infrastructure: models, repositories, publishers, consumers

planpals.chat
  presentation: views, serializers, permissions
  application: services, factories
  domain: repositories, events
  infrastructure: models, repositories, publishers, tasks, consumers

planpals.audit
  presentation: views, serializers
  application: services, repositories, factories
  domain: entities
  infrastructure: models, repositories

planpals.notifications
  presentation: views, serializers
  application: services, repositories, factories
  domain: entities, push ports
  infrastructure: models, repositories, publishers, push, tasks, consumers

planpals.analytics
  presentation: views, serializers
  application: services, repositories, factories
  domain: entities
  infrastructure: models, repositories, tasks

planpals.locations
  presentation: views
  infrastructure: Goong service adapter

planpals.shared
  cache, paginators, base models, base services, consumers, events, task helpers
```

### 3.3 Frontend Dependency Rule

```text
Pages/Widgets -> Riverpod providers/notifiers -> Repository -> API service/Auth session -> HTTP/WebSocket
DTOs are passive data objects.
UI does not call HTTP directly.
```

### 3.4 Frontend Module Map

```text
lib/presentation
  pages: auth, home, plans, groups, chat, notifications, analytics, users
  widgets: analytics, audit, chat, notifications, common

lib/core/riverpod
  auth_notifier
  repository_providers
  plans_notifier
  groups_notifier
  conversation_providers
  notifications_provider
  analytics_providers
  audit_logs_provider

lib/core/repositories
  user_repository
  friend_repository
  group_repository
  plan_repository
  conversation_repository
  notification_repository
  analytics_repository
  audit_log_repository
  location_repository

lib/core/services
  apis
  api_error
  error_display_service
  chat_websocket_service
  notification_websocket_service
  firebase_service
```

### 3.5 Circular Dependency Notes

No hard circular dependency is required for runtime behavior. The only sensitive coupling is audit-to-notification orchestration:

- `AuditLogService` can call an injected dispatcher.
- `notifications.application.factories.get_audit_log_notification_dispatcher()` lazy-imports Celery task wiring.
- This avoids a hard import cycle between audit and notification application modules.

---

## 4. Sequence Diagrams (Text)

### 4.1 Create Plan

```text
User
  -> Flutter Plan Form
  -> PlanRepository.createPlan()
  -> POST /api/v1/plans/
  -> PlanViewSet.create
  -> PlanService.create_plan
  -> CreatePlanHandler.handle
  -> PlanRepository.save_new
  -> DB: insert Plan
  -> EventPublisher.publish(PlanCreated)
  -> AuditLogService.log_action(CREATE_PLAN)
  -> AuditLogRepository.create_log
  -> DB: insert AuditLog
  -> audit notification dispatcher
  -> Celery: process_audit_log_notification_task
  -> NotificationService.notify_many
  -> NotificationRepository.bulk_create_notifications
  -> DB: insert Notification rows
  -> ChannelsNotificationPublisher.publish_created
  -> WebSocket user channel
  -> HTTP response serialized
  -> Flutter DTO mapping
  -> UI refresh
```

### 4.2 Join Group

```text
User
  -> Flutter Group Detail Page
  -> GroupRepository.joinGroup()
  -> POST /api/v1/groups/{id}/join/
  -> GroupViewSet.join
  -> GroupService.join_group
  -> JoinGroupHandler.handle
  -> GroupMembershipRepository.create
  -> DB: insert GroupMembership
  -> AuditLogService.log_action(JOIN_GROUP)
  -> DB: insert AuditLog
  -> Celery: process_audit_log_notification_task
  -> NotificationService.notify_many(admin recipients)
  -> DB: insert Notification rows
  -> Response
  -> Flutter groups notifier refresh
```

### 4.3 Send Message

```text
User
  -> Flutter Chat Page
  -> MessagesNotifier.sendTextMessage()
  -> ConversationRepository.sendTextMessage()
  -> POST /api/v1/conversations/{id}/send_message/
  -> ConversationViewSet.send_message
  -> ConversationService.create_message
  -> ChatRepository.create_message
  -> DB: insert ChatMessage
  -> DB: update Conversation.last_message_at
  -> Channels publisher -> conversation_{id}
  -> Optional push fan-out task
  -> Response with ChatMessage payload
  -> MessagesNotifier.addMessage()
  -> conversationListProvider invalidated
```

### 4.4 Notification Read Flow

```text
User
  -> NotificationListPage
  -> NotificationsNotifier.markAsRead()
  -> PATCH /api/v1/notifications/{id}/read/
  -> NotificationViewSet.mark_read
  -> NotificationService.mark_as_read
  -> NotificationRepository.mark_as_read
  -> DB: update Notification.is_read/read_at
  -> AuditLogService.log_action(NOTIFICATION_OPENED)
  -> DB: insert AuditLog
  -> ChannelsNotificationPublisher.publish_read
  -> unreadCountProvider updates
```

### 4.5 Async Audit -> Notification Flow

```text
State-changing command
  -> AuditLogService.log_action(...)
  -> AuditLogRepository.create_log
  -> DB: insert AuditLog
  -> audit notification dispatcher whitelist check
  -> Celery high_priority queue
  -> process_audit_log_notification_task
  -> compute recipients from GroupMembership / Plan membership / metadata
  -> fanout_group_notification_task
  -> NotificationService.notify_many
  -> DB: bulk insert Notification
  -> PushService.send(...)
  -> ChannelsNotificationPublisher.publish_created
```

### 4.6 Analytics Aggregation Flow

```text
Celery Beat (02:15 daily)
  -> aggregate_daily_metrics_task
  -> AnalyticsService.aggregate_daily_metrics(target_date)
  -> AnalyticsRepository.aggregate_day
  -> read AuditLog and Notification tables
  -> compute DAU/MAU/rates
  -> upsert DailyMetric(date)
  -> invalidate analytics cache
  -> later dashboard requests read only DailyMetric
```

---

## 5. Event Flow Map

### 5.1 Primary Events

| Event | Trigger | Immediate state change | Side effects |
|---|---|---|---|
| `PlanCreated` | Create plan command succeeds | `Plan` row inserted | Audit log, scheduled lifecycle tasks, notifications to participants |
| `PlanUpdated` | Update plan succeeds | `Plan` row updated | Audit log, cache invalidation, notifications to participants |
| `PlanCompleted` | Manual complete or scheduled completion | `Plan.status=completed` | Audit log `COMPLETE_PLAN`, realtime publish, analytics aggregate later |
| `GroupJoined` | Join group succeeds | `GroupMembership` row inserted | Audit log, notify group admins |
| `GroupLeft` | Leave group succeeds | `GroupMembership` row deleted | Audit log, notify group admins |
| `RoleChanged` | Admin changes member role | `GroupMembership.role` updated | Audit log, notify affected user |
| `MessageSent` | Chat message created | `ChatMessage` row inserted | Conversation timestamp update, websocket broadcast, optional push |
| `NotificationSent` | Notification service create/bulk-create | `Notification` row(s) inserted | WebSocket user event, optional FCM push |
| `NotificationOpened` | Notification marked read | `Notification.is_read=true` | Audit log, unread badge update, analytics aggregate later |
| `DailyMetricsAggregated` | Daily Celery beat task | `DailyMetric` upserted | Analytics caches invalidated |

### 5.2 Audit Action to Analytics Mapping

| Audit action | Analytics meaning |
|---|---|
| `CREATE_PLAN` | plan created |
| `COMPLETE_PLAN` | plan completed |
| `JOIN_GROUP` | group join event |
| any action with user actor | contributes to active user count |
| `NOTIFICATION_OPENED` | notification open count |

### 5.3 Audit Action to Notification Mapping

Only these audit actions are allowed to fan out notifications:

- `CREATE_PLAN`
- `UPDATE_PLAN`
- `DELETE_PLAN`
- `JOIN_GROUP`
- `LEAVE_GROUP`
- `CHANGE_ROLE`
- `DELETE_GROUP`

Explicitly excluded:

- `NOTIFICATION_OPENED`
- any unsupported future audit action until mapped intentionally

---

## 6. State Transitions

### 6.1 Plan State Machine

```text
upcoming
  -> ongoing      (manual start or scheduled Celery start task)
  -> cancelled    (manual cancel)

ongoing
  -> completed    (manual complete or scheduled Celery completion)
  -> cancelled    (manual cancel)

completed
  -> terminal

cancelled
  -> terminal
```

Rules:

- No draft state exists in the current model.
- Completed or cancelled plans cannot be edited.
- End date must be after start date.
- Group plan must have a group.
- Personal plan must not have a group.

### 6.2 Plan Activity State Machine

```text
not_completed <-> completed
```

Rules:

- Activity time must be inside the parent plan time range.
- Duration cannot exceed 24 hours.
- Estimated cost must be non-negative.
- Coordinates must be valid if present.

### 6.3 Group Membership State Machine

```text
absent
  -> member   (join/add member/create group initial members)
  -> admin    (create group admin seed)

member
  -> admin    (change_role promote)
  -> removed  (leave/remove/delete group)

admin
  -> member   (change_role demote)
  -> removed  (leave/remove/delete group, subject to admin invariant)
```

Rules:

- The group must always retain at least one admin.
- Group delete is owner-admin only.
- Group read access is member-only.

### 6.4 Friendship State Machine

```text
none
  -> pending

pending
  -> accepted
  -> rejected
  -> blocked
  -> none      (cancel)

accepted
  -> blocked
  -> none      (unfriend)

rejected
  -> pending   (new request after cooldown rules)

blocked
  -> none or pending depending on unblock + future request flow
```

### 6.5 Notification State Machine

```text
unread -> read
```

Rules:

- Notifications are user-owned.
- `read_all` is idempotent.
- Marking read creates audit evidence.

---

## 7. Data Flow Pipeline

### 7.1 Synchronous Read/Write Path

```text
Flutter UI
  -> Riverpod notifier/provider
  -> Repository
  -> AuthProvider adds OAuth token
  -> DRF endpoint
  -> Serializer validates request
  -> Application service / command handler
  -> Repository interface
  -> Infrastructure repository (ORM)
  -> MySQL
  -> Serializer / direct payload dict
  -> JSON response
  -> DTO mapping
  -> Riverpod state
  -> UI
```

### 7.2 Serialization and DTO Mapping

Backend:

- DRF `ModelSerializer` or plain `Serializer` shapes HTTP contracts.
- Some cached responses are built manually for speed, notably `/users/profile`.
- Audit, notifications, and analytics use explicit serializers with stable field names.

Frontend:

- DTOs in `lib/core/dtos` parse backend JSON.
- Repositories normalize pagination and errors.
- Providers keep UI state separate from DTO state.

### 7.3 Cache Touch Points

- `/users/profile` -> cacheable dict response
- plan summary -> cached statistics payload
- group detail -> per-user cached detail payload
- analytics summary/time series/top -> cached aggregate views
- websocket presence -> `ws_connected:{user_id}`
- unread chat count -> short TTL user cache
- plan reminder dedupe -> cache `add` key per plan/user/start time

### 7.4 Realtime Side Channel

```text
DB write
  -> application/publisher
  -> Channels group_send
  -> WebSocket client
  -> Riverpod notifier mutates in-memory state
```

---

## 8. API Contract Map

### 8.1 Global Rules

- Base API prefix: `/api/v1/`
- Auth: OAuth2 bearer token for all application endpoints unless noted
- Default pagination: `{"count","next","previous","results":[]}`
- Custom cursor pagination used by audit logs and notifications
- Conversation list intentionally uses custom response `{"conversations":[...],"count":N}`

### 8.2 Schema Aliases

```text
UserSummary:
  id, username, full_name, avatar_url, online flags, counts

PlanSummary:
  lightweight plan list item for feeds/home cards

PlanDetail:
  plan core fields + creator + group + activities + permission booleans

GroupSummary / GroupDetail:
  group metadata + memberships + counts + permission booleans

ConversationSummary:
  conversation metadata + last_message + unread_count

ChatMessageDetail:
  id, sender, type, content, attachments/location, timestamps, reply_to, delete/edit flags

CursorPage<T>:
  next, previous:null, has_more, page_size, results:[T]

NotificationPage:
  CursorPage<NotificationItem> + unread_count
```

### 8.3 OAuth and Session

| Endpoint | Method | Request schema | Response schema | Notes |
|---|---|---|---|---|
| `/o/token/` | POST | OAuth2 grant payload | access token + refresh token + expiry | Login/token refresh path |
| `/api/v1/auth/logout/` | POST | optional current token | success/message | Revokes token and sets offline |

### 8.4 Users and Friendship

| Endpoint | Method | Request schema | Response schema | Notes |
|---|---|---|---|---|
| `/api/v1/users/` | GET | none | current user summary wrapper | authenticated self shortcut |
| `/api/v1/users/` | POST | register fields | user/auth payload | registration |
| `/api/v1/users/profile/` | GET | none | profile dict including `is_staff` | cached |
| `/api/v1/users/update_profile/` | PUT/PATCH | editable profile fields | updated user | invalidates profile cache |
| `/api/v1/users/search/?q=` | GET | query string | list of `UserSummary` | search |
| `/api/v1/users/register_device_token/` | POST | `token`, `platform` | success/message | notification device token |
| `/api/v1/users/my_plans/?type=` | GET | `all|personal|group` | list of plans | user-scoped |
| `/api/v1/users/my_groups/` | GET | none | list of groups | user-scoped |
| `/api/v1/users/my_activities/` | GET | none | list of activities | user-scoped |
| `/api/v1/users/set_online_status/` | POST | `is_online` | success/message | presence |
| `/api/v1/users/friendship_stats/` | GET | none | count summary | stats |
| `/api/v1/users/recent_conversations/` | GET | none | recent conversation summaries | home/profile |
| `/api/v1/users/unread_count/` | GET | none | unread chat count | badge |
| `/api/v1/users/{id}/` | GET | none | user detail | target profile |
| `/api/v1/users/{id}/friendship_status/` | GET | none | status object | friend relation state |
| `/api/v1/users/{id}/unfriend/` | DELETE | none | success/message | friends only |
| `/api/v1/users/{id}/block/` | POST | none | success/message | non-self |
| `/api/v1/users/{id}/unblock/` | DELETE | none | success/message | blocker only |
| `/api/v1/friends/request/` | POST | target user id | success/message | creates pending friendship |
| `/api/v1/friends/requests/` | GET | none | pending/sent request lists | inbox |
| `/api/v1/friends/requests/{request_id}/action/` | POST | `action=accept|reject` | success/message | permission-checked |
| `/api/v1/friends/` | GET | none | friend list | accepted only |

### 8.5 Groups

| Endpoint | Method | Request schema | Response schema | Notes |
|---|---|---|---|---|
| `/api/v1/groups/` | GET | none | standard page of groups | member-visible groups |
| `/api/v1/groups/` | POST | `name`, `description`, media, `initial_members[]` | `GroupDetail` | initial friend seed; admin auto-created |
| `/api/v1/groups/{id}/` | GET | none | `GroupDetail` | member only |
| `/api/v1/groups/{id}/` | PUT/PATCH | editable group fields | updated detail | admin only |
| `/api/v1/groups/{id}/` | DELETE | none | success/message | owner-admin only |
| `/api/v1/groups/{id}/join/` | POST | none | success/message | joins group directly |
| `/api/v1/groups/{id}/leave/` | POST | none | success/message | leaves group |
| `/api/v1/groups/{id}/add_member/` | POST | `user_id` | success/message | admin only |
| `/api/v1/groups/{id}/remove_member/` | POST | `user_id` | success/message | admin only |
| `/api/v1/groups/{id}/change_role/` | POST | `user_id`, `role` | success/message | admin only |
| `/api/v1/groups/{id}/send_message/` | POST | message payload | message result | group member only |
| `/api/v1/groups/{id}/recent_messages/` | GET | none | recent chat summaries | member only |
| `/api/v1/groups/{id}/unread_count/` | GET | none | unread counter | member only |
| `/api/v1/groups/{id}/admins/` | GET | none | admin user list | member only |
| `/api/v1/groups/{id}/plans/` | GET | none | plan list | member only |
| `/api/v1/groups/my_groups/` | GET | none | list | current user memberships |
| `/api/v1/groups/created_by_me/` | GET | none | list | ownership |
| `/api/v1/groups/search/?q=` | GET | query string | list | search |

### 8.6 Plans and Activities

| Endpoint | Method | Request schema | Response schema | Notes |
|---|---|---|---|---|
| `/api/v1/plans/` | GET | standard paging/filter query | standard page of `PlanSummary` or detail serializer depending endpoint | feed |
| `/api/v1/plans/` | POST | `title`, `description`, `start_date`, `end_date`, `is_public`, `plan_type`, `group_id` | `PlanDetail` | group membership checked for group plans |
| `/api/v1/plans/{id}/` | GET | none | `PlanDetail` | creator/group member/public access |
| `/api/v1/plans/{id}/` | PUT/PATCH | editable plan fields | updated plan | creator or group admin |
| `/api/v1/plans/{id}/` | DELETE | none | success/message | creator only |
| `/api/v1/plans/my_plans/?type=` | GET | `all|personal|group` | plan list | personal dashboard |
| `/api/v1/plans/joined/` | GET | none | plan list | joined/collaborative |
| `/api/v1/plans/public/` | GET | none | public plan list | public browse |
| `/api/v1/plans/{id}/join/` | POST | none | success/message | public plan join |
| `/api/v1/plans/{id}/activities_by_date/?date=` | GET | date | activity list for that date | filtered by date |
| `/api/v1/plans/{id}/collaborators/` | GET | none | user list | collaborators/group members |
| `/api/v1/plans/{id}/summary/` | GET | none | plan statistics summary | cached |
| `/api/v1/plans/{id}/schedule/` | GET | none | schedule by date | grouped activities |
| `/api/v1/plans/{id}/create_activity/` | POST | activity payload | activity detail | creator or group admin |
| `/api/v1/plans/{id}/activities/{activity_id}/` | PUT/PATCH | activity payload | updated activity | creator or group admin |
| `/api/v1/plans/{id}/activities/{activity_id}/` | DELETE | none | success/message | creator or group admin |
| `/api/v1/plans/{id}/activities/{activity_id}/complete/` | POST | none | updated activity | toggles completion |
| `/api/v1/activities/` | CRUD | activity payload | activity detail | DRF activity viewset |
| `/api/v1/activities/by_plan/?plan_id=` | GET | plan id | activity list | filtered |
| `/api/v1/activities/by_date_range/?start_date=&end_date=` | GET | date range | activity list | filtered |
| `/api/v1/activities/upcoming/?limit=` | GET | limit | activity list | upcoming |
| `/api/v1/activities/search/?q=&plan_id=` | GET | search query | activity list | search |

### 8.7 Chat and Conversations

| Endpoint | Method | Request schema | Response schema | Notes |
|---|---|---|---|---|
| `/api/v1/messages/` | CRUD | chat message serializer payload | `ChatMessageDetail` | direct viewset path |
| `/api/v1/messages/by_group/?group_id=&limit=&before_id=` | GET | group id + paging | message list | group chat history |
| `/api/v1/messages/search/?q=&group_id=` | GET | search query | message list | search |
| `/api/v1/messages/recent/?limit=` | GET | limit | message list | recents |
| `/api/v1/conversations/` | GET | optional `q` | `{"conversations":[ConversationSummary], "count":N}` | custom list contract |
| `/api/v1/conversations/` | POST | conversation create payload | conversation detail | generic create |
| `/api/v1/conversations/{id}/` | GET | none | conversation detail | participant only |
| `/api/v1/conversations/create_direct/` | POST | `user_id` | conversation detail | requires friendship |
| `/api/v1/conversations/{id}/messages/?limit=&before_id=` | GET | cursor via `before_id` | message page | read-only fetch |
| `/api/v1/conversations/{id}/send_message/` | POST | text/image/file/location payload | created message | explicit send |
| `/api/v1/conversations/{id}/mark_read/` | POST | `message_ids[]` | success/message | explicit mark-read |

### 8.8 Audit Logs

| Endpoint | Method | Request schema | Response schema | Notes |
|---|---|---|---|---|
| `/api/v1/audit-logs/` | GET | `user_id`, `action`, `resource_type`, `date_from`, `date_to`, `cursor`, `page_size` | `CursorPage<AuditLogItem>` | access-filtered |
| `/api/v1/audit-logs/resource/{resource_type}/{resource_id}/` | GET | same filters | `CursorPage<AuditLogItem>` + resource ids | resource-scoped |

`AuditLogItem`:

```text
id, user_id, user, action, resource_type, resource_id, metadata, created_at
```

### 8.9 Notifications

| Endpoint | Method | Request schema | Response schema | Notes |
|---|---|---|---|---|
| `/api/v1/notifications/` | GET | `is_read`, `cursor`, `page_size` | `NotificationPage` | owner-only |
| `/api/v1/notifications/unread-count/` | GET | none | `{"unread_count": int}` | badge |
| `/api/v1/notifications/{id}/read/` | PATCH | none | `{"message": "Notification marked as read"}` | idempotent for current user |
| `/api/v1/notifications/read-all/` | PATCH | none | `{"message": "...", "updated_count": int}` | bulk read |

`NotificationItem`:

```text
id, user_id, type, title, message, data, is_read, read_at, created_at
```

### 8.10 Analytics

| Endpoint | Method | Request schema | Response schema | Notes |
|---|---|---|---|---|
| `/api/v1/analytics/summary/?range=` | GET | `range in {7d,30d,90d,180d}` | `AnalyticsSummary` | staff only, cached |
| `/api/v1/analytics/timeseries/?metric=&range=` | GET | `metric` + `range` | `{metric, range, points[]}` | staff only, cached |
| `/api/v1/analytics/top/?range=&limit=` | GET | `range`, `limit<=20` | `{range, plans[], groups[]}` | staff only, cached |

### 8.11 Location Services

Only these location endpoints are routed publicly through `planpals.urls`:

| Endpoint | Method | Request schema | Response schema | Notes |
|---|---|---|---|---|
| `/api/v1/location/reverse-geocode/` | POST | `latitude`, `longitude` | address payload | Goong-backed reverse geocode |
| `/api/v1/location/search/?q=` | GET | query string `q` | `{"results":[...]}` | place search |
| `/api/v1/location/autocomplete/?input=` | GET | `input` | `{"predictions":[...]}` | autocomplete |
| `/api/v1/location/place-details/?place_id=` | GET | `place_id` | place detail payload | details |

---

## 9. Permission Model

### 9.1 Role Vocabulary

```text
authenticated user
self
friend
group member
group admin
group owner-admin (Group.admin)
plan creator
plan collaborator/group participant
chat participant
staff
```

### 9.2 Action -> Required Role

| Action | Required role / rule |
|---|---|
| View own profile | self |
| Update profile | self |
| Search users | authenticated |
| Send friend request | authenticated, not self, not blocked |
| Accept/reject friend request | receiver only |
| View group detail | group member |
| Edit group | any group admin |
| Delete group | owner-admin only |
| Join group | authenticated user, service rule |
| Add/remove member | group admin |
| Change member role | group admin |
| Create personal plan | authenticated |
| Create group plan | group member with edit ability |
| View plan | creator, group member, or public plan |
| Edit plan | creator or group admin |
| Delete plan | creator only |
| Modify plan activity | creator or group admin |
| Join public plan | not creator, public access |
| Create direct conversation | authenticated and friendship exists |
| View conversation | participant only |
| Send message | conversation participant or group member |
| Edit message | sender only, text only, within 15 minutes, non-system |
| Delete message | sender or group admin |
| View audit log list | authenticated + access-filtered by owned/accessible resources |
| View resource audit log | group member / plan participant / actor of deletion event |
| View notifications | owner only |
| Mark notification read | owner only |
| View analytics | staff only |

### 9.3 Permission Enforcement Layers

- DRF permission classes guard broad access.
- Application services and handlers enforce domain-specific rules.
- Audit repository applies resource-aware visibility filters.
- Chat service validates friendship and conversation participation.

---

## 10. Caching Flow

### 10.1 Cache Usage Map

| Cache key | Source | TTL | Invalidation |
|---|---|---:|---|
| `v1:user:profile:{user_id}` | `UserService.get_user_profile_cached()` | 120s | profile update, friendship-affecting self updates, self-heal on schema mismatch |
| `v1:plan:summary:{plan_id}` | `PlanService.get_plan_statistics()` | 180s | plan update/delete, summary-affecting changes |
| `v1:group:detail:{group_id}:u{user_id}` | `GroupService.get_group_detail_cached()` | 180s | group membership/update/delete via pattern delete |
| `v1:analytics:summary:{range}` | analytics summary | 300s | daily aggregate job invalidates all analytics cache |
| `v1:analytics:timeseries:{metric}:{range}` | analytics time series | 600s | daily aggregate job invalidates all analytics cache |
| `v1:analytics:top:{range}:limit:{n}` | analytics top entities | 600s | daily aggregate job invalidates all analytics cache |
| `user_unread_count_{user_id}` | unread chat badge | 30s | message create/read clears user cache |
| `ws_connected:{user_id}` | websocket presence | 300s | connection/disconnection |
| `plan_reminder:{plan_id}:{user_id}:{start_iso}` | notification reminder dedupe | 36h | expires naturally |

### 10.2 Cache Read/Write Pattern

```text
Request
  -> CachePort.get_or_set(key)
    -> cache hit: return payload
    -> cache miss: compute from repository
      -> DB read
      -> cache write
      -> return payload
```

### 10.3 Runtime Behavior

- In production Redis can back cache and Channels.
- In local development cache can fall back to `LocMemCache`.
- Cache failures are handled defensively; the system should still function without cache.

---

## 11. Async Flow (Celery)

### 11.1 Queues

| Queue | Purpose | Examples |
|---|---|---|
| `high_priority` | user-triggered fan-out | notification send, audit notification processing, chat push |
| `default` | general async work | default routing fallback |
| `plan_status` | scheduled lifecycle transitions | plan start/complete tasks |
| `low_priority` | batch/periodic work | analytics aggregation, reminder dispatch, cleanup |

### 11.2 Scheduled Jobs

| Task | Schedule | Effect |
|---|---|---|
| `aggregate_daily_metrics_task` | daily 02:15 | upsert `DailyMetric`, invalidate analytics cache |
| `cleanup_expired_offline_events_task` | daily 03:00 | cleanup |
| `cleanup_invalid_fcm_tokens_task` | weekly Sunday 04:00 | token hygiene |
| `dispatch_plan_reminders_task` | hourly | send reminder notifications for plans starting within 24h |

### 11.3 Event -> Task -> Worker -> Effect

```text
AuditLog created
  -> dispatcher whitelist
  -> process_audit_log_notification_task
  -> fanout_group_notification_task
  -> NotificationService.notify_many
  -> DB + realtime + push

Plan approaching start time
  -> dispatch_plan_reminders_task
  -> dedupe with cache.add
  -> NotificationService.notify_many
  -> DB + push

Daily beat
  -> aggregate_daily_metrics_task
  -> AnalyticsRepository.aggregate_day
  -> DailyMetric upsert
  -> analytics cache invalidated
```

### 11.4 Reliability Model

- `acks_late=True` on important tasks
- soft/hard time limits
- retry with backoff for notification tasks
- broker/result fallback to in-memory in dev if Redis env is absent

---

## 12. Frontend State Graph

### 12.1 Root Provider Wiring

```text
ProviderScope
  -> authNotifierProvider (override with pre-initialized AuthProvider)
  -> repository_providers
     -> all repositories depend on authNotifierProvider
  -> feature notifiers/providers consume repositories
```

### 12.2 Major Providers

#### Authentication

- `authNotifierProvider`: exposes initialized `AuthProvider`; source of token/session state.

#### Plans

- `plansNotifierProvider`: `AsyncNotifier<PlansFeedState>`
- `plansListProvider`: derived current list
- `recentPlansProvider`: top 5 plans
- `plansFeedScrollOffsetProvider`: scroll restoration

#### Groups

- `groupsNotifierProvider`: `AsyncNotifier<List<GroupSummary>>`
- `activeGroupsProvider`: top 5 groups

#### Chat

- `conversationListProvider`: list of conversations
- `totalUnreadCountProvider`: derived unread count
- `conversationSearchProvider(query)`: server-side search
- `messagesProvider(conversationId)`: paged messages state
- `typingUsersProvider(conversationId)`: ephemeral typing state
- `chatWebSocketServiceProvider(conversationId)`: realtime transport

#### Notifications

- `notificationsProvider`: `AsyncNotifier<NotificationFeedState>`
- `unreadCountProvider`: unread notification badge with websocket + polling fallback
- `notificationWebSocketServiceProvider`: realtime transport

#### Audit Logs

- `auditLogsProvider(filter)`
- `resourceAuditLogsProvider(query)`

#### Analytics

- `analyticsRangeProvider`
- `analyticsChartMetricProvider`
- `analyticsSummaryProvider`
- `analyticsTimeSeriesProvider`
- `analyticsTopEntitiesProvider`

### 12.3 Data Path

```text
Widget
  -> ref.watch(provider)
  -> notifier/repository
  -> API
  -> DTO parse
  -> AsyncValue<T>
  -> UI state branch
```

---

## 13. UI State Machine

Most async screens follow the same state machine:

```text
loading
  -> success(non-empty)
  -> empty
  -> error

success(non-empty)
  -> refreshing
  -> loading_more
  -> error(loadMore only, list preserved)

empty
  -> refreshing

error
  -> retry -> loading
```

Actual examples:

- Plans feed preserves existing items during load-more failure.
- Notifications feed supports optimistic read and rollback on failure.
- Audit log list supports filter refresh and deduplicated page append.
- Analytics page loads summary, one selected time series, and top entities independently.

---

## 14. Pagination Flow

### 14.1 Backend Patterns

```text
Standard DRF page:
  count, next, previous, results[]

Cursor page:
  next, previous:null, has_more, page_size, results[]

Conversation page:
  conversations[], count

Message page:
  nextCursor/before_id style conversation history pagination
```

### 14.2 Frontend Merge Strategy

- Track already loaded page URLs or cursors.
- Ignore duplicate page loads.
- Merge by entity id, not raw append.
- Preserve existing items on load-more error.
- Use optimistic updates for single-row read actions.

Concrete implementations:

- `PlansNotifier`: keeps `_loadedPageUrls`, merges unique plan ids.
- `NotificationsNotifier`: keeps `_loadedPageUrls`, merges unique notification ids, updates unread count.
- `AuditLogsNotifier` and `ResourceAuditLogsNotifier`: same cursor merge strategy.
- `MessagesNotifier`: uses `before_id` cursor and appends older messages.

---

## 15. Performance Model

### 15.1 Backend

- Indexed tables:
  - audit logs: `(user, created_at)`, `(resource_type, resource_id)`, `(action)`, `(created_at, id)`
  - notifications: `(user, is_read)`, `(created_at)`, `(type)`, `(user, created_at)`, `(created_at, id)`
  - analytics: index on `date`
  - plans, activities, groups, friendships, chat models include query-oriented indexes
- Read-heavy endpoints use cache where beneficial.
- Analytics uses pre-aggregated `DailyMetric`; no heavy audit scans at request time.
- Notification fan-out uses `bulk_create_notifications()` and Celery.
- Chat and audit log queries use `select_related` and scoped filters to avoid N+1.

### 15.2 Frontend

- List screens use incremental loading or capped home summaries.
- Riverpod providers isolate rebuild scope.
- Analytics loads only the selected chart metric, not all series.
- Notification unread badge uses websocket first, polling fallback second.
- Chat typing/read state is ephemeral and conversation-scoped.

### 15.3 Known Non-Uniform Areas

- Groups feed currently loads as a full list, not infinite scroll.
- Conversation list uses a custom response instead of standard pagination.
- Location endpoints are pass-through service calls and depend on external latency.

---

## 16. Failure Modes

| Failure mode | Symptom | Current handling |
|---|---|---|
| API contract mismatch | DTO parse error or null handling issue | serializers/DTOs aligned; critical custom contracts documented here |
| Permission denial | 403 | DRF permissions + service checks |
| Cache stale | outdated summary/profile/detail | targeted invalidation and short TTLs |
| Cache unavailable | cache miss or warning | graceful fallback to DB/local memory |
| Redis unavailable in dev | no shared cache/channel broker | LocMem cache and in-memory Channels fallback |
| Celery lag | delayed notifications/analytics | queues separated by priority; dashboard still serves last aggregate |
| Push failure | no mobile push | notification row still created; realtime/in-app remains available |
| WebSocket disconnect | stale badges/typing | reconnect logic; polling fallback for unread notifications |
| External map service failure | place lookup unavailable | location endpoints return empty/fallback/error payloads |
| OAuth token expiry | 401 | frontend auth session refresh path |
| Deleted resource referenced in audit/analytics | missing entity name | metadata fallback names used in audit/analytics top entity build |

---

## 17. Invariants (Very Important)

These invariants must never be violated.

### Identity and Friendship

- A user cannot friend themselves.
- Friendship canonical ordering is enforced by `(user_a, user_b)` unique constraint.
- Friendship initiator must be one of the two participants.

### Groups

- Every persisted group membership row is unique per `(user, group)`.
- A group must always retain at least one admin.
- Group detail and messages require membership.

### Plans

- `plan_type` is derived from `group`:
  - `group is null` -> personal
  - `group is not null` -> group
- Personal plans cannot reference a group.
- Group plans must reference a group.
- `end_date > start_date`.
- Only creator or authorized admins can mutate plans.

### Activities

- Activity must stay within parent plan date range.
- Activity `end_time > start_time`.
- Activity duration must not exceed 24 hours.
- Activity estimated cost cannot be negative.

### Chat

- Direct conversation must have `user_a` and `user_b`.
- Group conversation must reference exactly one group.
- System messages cannot have a sender.
- Location messages must have coordinates.

### Audit and Notification

- Audit logs are written after successful state change, not from models or views.
- Only whitelisted audit actions trigger notification tasks.
- Notification ownership is immutable.
- Marking notifications read is the only source of `NOTIFICATION_OPENED` audit evidence.

### Analytics

- Dashboard reads only from `DailyMetric` plus cached summaries, never live full-history scans.
- Notification open rate is derived from `notifications_opened / notifications_sent`.
- Plan creation/completion/group join rates are defined relative to active user totals in the selected window.

---

## 18. Extension Rules

To extend the system safely:

### 18.1 Add a New Domain Feature

1. Define domain entities/enums/events in `domain/`.
2. Define repository interfaces in `domain/` or `application/`.
3. Implement use cases in `application/services.py` or command handlers.
4. Implement ORM repositories and models in `infrastructure/`.
5. Expose HTTP API in `presentation/views.py` and serializers.
6. Add frontend DTO, repository method, provider/notifier, and page/widget.

### 18.2 Add a New Audit-Tracked Action

1. Add new `AuditAction`.
2. Emit it only after successful state change.
3. Decide whether it should trigger notifications.
4. If yes, add it to the notification dispatcher whitelist and mapping task.
5. Decide whether analytics should aggregate it.

### 18.3 Add a New Notification Type

1. Add `NotificationType`.
2. Add formatting logic in `NotificationService._format_content`.
3. Add payload conventions in notification `data`.
4. Add push mapping if required.
5. Update Flutter DTO/UI rendering if type-specific handling is needed.

### 18.4 Add a New Analytics Metric

1. Add enum value to `AnalyticsMetric`.
2. Extend `DailyMetric` if the metric must be materialized.
3. Update `AnalyticsRepository.aggregate_day()`.
4. Update summary/time series serializers.
5. Add frontend DTO enum and chart label mapping.
6. Invalidate analytics cache when aggregate shape changes.

### 18.5 Safe Change Checklist for AI Agents

- Do not put business logic in Django models or DRF views.
- Do not bypass repositories with raw ORM from application services.
- Do not add new realtime payload shapes without updating DTOs/providers.
- Do not add analytics queries that scan `AuditLog` per request.
- Preserve existing pagination shapes unless the frontend is updated in the same change.
- Preserve role invariants, especially the "group must always have an admin" rule.

---

## 19. Machine-Readable Summary

```json
{
  "system": "PlanPal",
  "architecture": {
    "backend": ["presentation", "application", "domain", "infrastructure"],
    "frontend": ["presentation", "riverpod", "repositories", "services", "dtos"],
    "style": ["layered", "event-enriched", "async side effects", "cache-assisted"]
  },
  "entities": [
    "User",
    "Friendship",
    "FriendshipRejection",
    "Group",
    "GroupMembership",
    "Plan",
    "PlanActivity",
    "Conversation",
    "ChatMessage",
    "MessageReadStatus",
    "AuditLog",
    "Notification",
    "UserDeviceToken",
    "DailyMetric"
  ],
  "actions": [
    "register",
    "login",
    "send_friend_request",
    "accept_friend_request",
    "create_group",
    "join_group",
    "leave_group",
    "change_role",
    "create_plan",
    "update_plan",
    "delete_plan",
    "complete_plan",
    "create_activity",
    "send_message",
    "mark_notification_read",
    "view_analytics"
  ],
  "audit_actions": [
    "CREATE_PLAN",
    "UPDATE_PLAN",
    "DELETE_PLAN",
    "COMPLETE_PLAN",
    "JOIN_GROUP",
    "LEAVE_GROUP",
    "CHANGE_ROLE",
    "DELETE_GROUP",
    "NOTIFICATION_OPENED"
  ],
  "notification_types": [
    "PLAN_REMINDER",
    "GROUP_JOIN",
    "GROUP_INVITE",
    "ROLE_CHANGED",
    "PLAN_UPDATED",
    "NEW_MESSAGE"
  ],
  "analytics_metrics": [
    "dau",
    "mau",
    "plans_created",
    "plans_completed",
    "plan_creation_rate",
    "plan_completion_rate",
    "group_joins",
    "group_join_rate",
    "notification_open_rate"
  ],
  "flows": [
    "ui -> provider -> repository -> api -> service -> repository -> db -> serializer -> dto -> ui",
    "command success -> audit log -> celery notification task -> notification rows -> websocket/push",
    "notification read -> audit log NOTIFICATION_OPENED -> daily analytics aggregate",
    "daily beat -> aggregate audit and notification data -> upsert DailyMetric -> cache invalidation"
  ],
  "caches": [
    "user_profile",
    "plan_summary",
    "group_detail",
    "analytics_summary",
    "analytics_timeseries",
    "analytics_top",
    "user_unread_count",
    "ws_connected",
    "plan_reminder_dedupe"
  ],
  "queues": {
    "high_priority": [
      "send_notification_task",
      "fanout_group_notification_task",
      "process_audit_log_notification_task",
      "chat push fanout"
    ],
    "default": ["general async work"],
    "plan_status": ["start_plan_task", "complete_plan_task"],
    "low_priority": [
      "aggregate_daily_metrics_task",
      "dispatch_plan_reminders_task",
      "cleanup_expired_offline_events_task",
      "cleanup_invalid_fcm_tokens_task"
    ]
  },
  "websocket_routes": [
    "/ws/chat/{conversation_id}/",
    "/ws/plans/{plan_id}/",
    "/ws/groups/{group_id}/",
    "/ws/user/",
    "/ws/notifications/"
  ],
  "permissions": {
    "analytics": "staff_only",
    "notifications": "owner_only",
    "group_detail": "member_only",
    "group_edit": "admin_only",
    "group_delete": "owner_admin_only",
    "plan_view": "creator_or_group_member_or_public",
    "plan_edit": "creator_or_group_admin",
    "chat_message_edit": "sender_text_only_within_15_minutes",
    "audit_resource_view": "resource_access_required"
  },
  "invariants": [
    "group_must_have_admin",
    "personal_plan_has_no_group",
    "group_plan_has_group",
    "plan_end_after_start",
    "activity_within_plan_range",
    "friendship_unique_per_user_pair",
    "direct_conversation_has_two_users",
    "group_conversation_has_group",
    "analytics_reads_preaggregated_data"
  ]
}
```

---

## 20. Final System Summary

PlanPal is a layered system with explicit boundaries between presentation, application, domain, and infrastructure. Its behavior is request-driven at the edge, audit-enriched for traceability, notification-aware for user feedback, and analytics-backed through pre-aggregation rather than live expensive queries.

Operationally, the system is event-oriented even though it is not a full event-sourced architecture. State changes happen in transactional application services and command handlers. Audit logs provide durable event evidence, Celery handles heavy side effects, Channels handles realtime fan-out, and Redis-backed caches reduce repeated read cost.

For AI agents, the safe modification model is:

```text
Understand the entity and invariant first.
Modify application service / handler behavior next.
Keep persistence in repositories.
Keep transport contracts stable or update DTOs/providers together.
Route heavy side effects to Celery.
Use audit logs as the canonical behavioral history.
Use DailyMetric as the canonical analytics read model.
```
