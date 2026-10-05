# PlanPal - Collaborative Travel Planning Platform

[![Flutter](https://img.shields.io/badge/Flutter-3.32%2B-02569B?logo=flutter)](https://flutter.dev/)
[![Django](https://img.shields.io/badge/Django-5.2%2B-092E20?logo=django)](https://www.djangoproject.com/)
[![DRF](https://img.shields.io/badge/DRF-3.14%2B-red)](https://www.django-rest-framework.org/)
[![Channels](https://img.shields.io/badge/Django%20Channels-WebSocket-blue)](https://channels.readthedocs.io/)
[![Celery](https://img.shields.io/badge/Celery-Async%20Jobs-37814A)](https://docs.celeryq.dev/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> PlanPal is a production-oriented mobile travel planning system with group collaboration, realtime chat, plan activities, budget tracking, audit logs, notifications, analytics, map/location sharing, and multilingual Flutter UI.

---

## Try It Now

| Platform | Link |
|----------|------|
| Android APK | [Download latest release](https://github.com/trieuvyynXLe0/PlanPalApp/releases/latest) |
| Live API Docs | [Swagger UI](https://planpal-backend.fly.dev/swagger/) |
| Admin Panel | [Django Admin](https://planpal-backend.fly.dev/admin/) |

---

## Demo Account

**Admin account**

```text
username: admin
password: 123
```

**User 1**

```text
username: u1
password: 12345678
```

**User 2**

```text
username: u2
password: 12345678
```

> Demo accounts depend on the target deployment database. For local development, create users through Django Admin, fixtures, or the mobile registration flow.


## NOTE: The app is NOT available from 09:00 PM to 08:00 AM. ⏲️

## Quick Start

### Backend Local Setup

```bash
git clone https://github.com/trieuvyynXLe0/PlanPalApp.git
cd PlanPalApp/planpalapp

python -m venv ..\.venv
..\.venv\Scripts\activate
..\.venv\Scripts\python.exe -m pip install -r requirements.txt

cd ..
Copy-Item .\planpalapp\.env.local.example .\planpalapp\.env.local
.\scripts\run_backend.ps1 -Environment local -Component migrate
.\scripts\run_backend.ps1 -Environment local -Component web
```

Do not start Django with a global `python` installation. In particular, a
different global `redis` package can cause WebSocket channel-layer timeouts
that do not reproduce in the project virtual environment.

### Redis, Celery Worker, and Celery Beat

Redis is required for production-grade cache, Channels, Celery queues, notifications, analytics jobs, and pending email verification.

```bash
docker run -d --name planpal-redis -p 6379:6379 redis:7
```

Run worker and beat in separate terminals:

```bash
cd planpalapp
..\.venv\Scripts\activate
python -m celery -A planpalapp worker -l info --pool=solo -Q high_priority,default,plan_status,low_priority
```

```bash
cd planpalapp
..\.venv\Scripts\activate
python -m celery -A planpalapp beat -l info
```

### Frontend Local Setup

```bash
flutter pub get --directory planpal_flutter
.\scripts\run_flutter.ps1 -Environment local -Action run
```

Environment switching does not require editing source files. Use
`PLANPAL_ENV=local|test|production` for Django and
`--dart-define=APP_ENV=local|production` for Flutter. See
[`docs/ENVIRONMENTS.md`](docs/ENVIRONMENTS.md) for emulator, physical-device,
testing, APK build, and production deployment instructions.

**Requirements:** Python 3.11+, Flutter 3.32+, Dart 3.8+, MySQL or compatible database, Redis 7+, Android Studio Emulator or physical Android device.

---

## Production Deploy

For a cost-conscious production deployment, PlanPal runs on one application
machine. Supervisor starts Daphne, one Celery worker, and exactly one Celery
Beat scheduler in the same container. MySQL and Redis remain managed external
services; Redis is never started inside the application container.

```bash
flyctl auth login
flyctl deploy -a planpal-backend
```

Check logs:

```bash
flyctl logs -a planpal-backend
```

Programs in the single application container:

- `web`: Daphne serving REST, health checks, and WebSocket traffic.
- `worker`: Celery consumers for all configured queues.
- `beat`: exactly one Celery Beat scheduler per environment.
- external Redis: TLS/password-protected broker, cache, and Channels layer.

Configure `REDIS_URL` as a password-authenticated `rediss://` URL and set
`REQUIRE_EXTERNAL_REDIS=true`. Keep exactly one Fly machine while this runtime
topology is used; scaling beyond one machine would start a second Beat scheduler
and duplicate periodic work:

```bash
fly scale count 1 -a planpal-backend
```

Liveness is exposed at `/health/live`; readiness at `/health/ready` checks the
database and Redis. Production logs are JSON and every HTTP response carries
`X-Request-ID`. See `docs/DEPLOYMENT_RUNBOOK.md` for backup, migration, rollout,
rollback, and smoke-test checklists.

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| Mobile | Flutter, Dart, Material 3 |
| State Management | Riverpod, AsyncNotifier/StateNotifier patterns |
| HTTP Client | Dio, OAuth2 auto-refresh integration |
| Realtime | WebSocket client, Django Channels |
| Backend | Django 5.2, Django REST Framework, ASGI/Daphne |
| Authentication | OAuth2 access/refresh token, email OTP verification |
| Database | MySQL in production, configurable via `DATABASE_URL` |
| Cache/Queue | Redis, django-redis, Celery, Celery Beat |
| File Storage | Cloudinary |
| Push Notification | Firebase Cloud Messaging structure |
| Maps/Location | Goong vector maps via MapLibre, Geolocator, Goong location API |
| Charts | fl_chart |
| API Documentation | Swagger / Redoc via drf-yasg / OpenAPI |
| Deployment | Docker, Supervisor single-machine runtime, managed Redis/MySQL |
| Observability | JSON logs, request correlation, health probes, optional Sentry |

---

## Key Features

### Authentication and Account Security

- OAuth2 token-based login with access token and refresh token.
- Token-aware login guard for unverified accounts.
- Email verification by 6-digit OTP code.
- Registration is stored as pending data first; user account is created only after successful OTP verification.
- Secure mobile token storage through Flutter auth session integration.
- Profile management with avatar upload, bio, phone number, and online status.

### Social and Groups

- Friend request, accept/reject, friend list, and user profile views.
- Group creation and group detail screens.
- Group membership roles:
  - `admin`: manages members, roles, group settings, and group plans.
  - `plan_creator`: can create group plans but cannot manage roles.
  - `member`: can participate and view allowed group data.
- Admin can grant or revoke plan creator permission.
- Object-level permission checks for groups, plans, budget, and conversations.
- Group polls with single/multiple choice, member-only voting, and controlled closing.

### Plans and Activities

- Personal and group travel plans.
- Plan lifecycle states including upcoming, ongoing, completed, and cancelled.
- Cancel plan action restricted to upcoming plans only.
- Activity scheduling with conflict detection.
- Activity creation, update, completion toggle, and audit log tracking.
- Realtime collaborative activity editing:
  - Activity `version` field.
  - Optimistic locking.
  - Conflict response with server version and client attempted changes.
  - Plan WebSocket channel for live activity updates.
- Group availability polls before plan creation with available/maybe/unavailable RSVP.
- Plan assignments and checklist items with assignee, deadline, status, and aggregate progress.
- Plan/activity discussion with replies-ready data model, `@username` mentions, reactions, and pinned content.
- Clone existing plans as a new schedule or reusable template while preserving activity offsets.
- Calendar export through standard ICS files and per-activity Google Calendar links.

### Chat and Conversations

- Direct and group conversations.
- Text, image, file, audio/video attachment, and location messages.
- Cloudinary-backed media attachments.
- Read status and unread count.
- Chat WebSocket updates with reconnect behavior.
- Last message contract for conversation list.
- Global search across only the plans, groups, conversations, and message content visible to the signed-in user.

### Map and Location

- Home map action opens current-location map screen.
- Device GPS support through Geolocator.
- Current location marker and coordinate display.
- Send current location to a selected conversation.
- Location picker with search, reverse geocoding, and place details API.
- Consent-based live location sharing with a 5-480 minute expiry and automatic server cleanup.

### Budget Tracking

- One budget per plan.
- Expenses scoped to plan and user.
- Budget summary:
  - total budget
  - total spent
  - remaining budget
  - per-user breakdown
- Expense list with pagination, filter, sort, and quick add.
- Audit log and notification integration for budget updates and expenses.

### Audit Log

- Append-only audit log architecture.
- Tracks important actions across plan, group, activity, budget, expense, notification, and system events.
- Resource-scoped audit history for plan and group detail pages.
- Filters by action, user, and date range.
- Used as primary behavioral data source for analytics.

### Notifications

- In-app notifications with unread count.
- Notification types include plan reminders, group join, group invite, role changed, plan updated, new message, budget alerts, and system events.
- Async notification dispatch through Celery.
- Realtime notification channel through WebSocket.
- Push notification abstraction prepared for FCM.
- Device token registration endpoint.
- Per-user push toggle, timezone-aware quiet hours, and daily unread digest.

### Offline Resilience

- User-scoped drafts for group, plan, and activity create/edit wizards.
- Sequential mutation queue for supported offline actions with automatic resume sync.
- Idempotency keys prevent duplicate polls or live-location shares after ambiguous network failures.
- Permanent 4xx failures are separated into a bounded dead-letter queue rather than retried forever.

### Analytics Dashboard

- Pre-aggregated analytics from audit logs and notification activity.
- Daily metrics model for efficient dashboard reads.
- Dashboard summary and time series APIs.
- KPI cards and charts in Flutter.
- Redis cache for frequent analytics reads.
- Celery Beat daily aggregation job.

### Localization and Theme

- Vietnamese and English language support.
- Runtime language switching.
- Light mode and dark mode support.
- Friendly mobile error messages instead of raw backend exceptions.

---

## Architecture

PlanPal follows a Clean Architecture inspired module layout.

```text
Presentation -> Application -> Domain
Infrastructure -> Application + Domain
Shared -> cross-cutting utilities and ports
```

### Backend Bounded Contexts

```text
planpals/
├── auth/           # users, OAuth2, profile, friendship, email OTP, presence
├── groups/         # group lifecycle, membership, role management
├── plans/          # plans, activities, lifecycle, collaboration
├── chat/           # conversations, messages, attachments, read status
├── budgets/        # budget and expense tracking
├── audit/          # append-only audit logs
├── notifications/  # in-app notifications, push abstraction, realtime events
├── analytics/      # daily metrics, dashboard summary, time series
├── locations/      # reverse geocode, search, autocomplete, place details
├── integrations/   # cross-context notification integration
└── shared/         # cache keys, pagination, exceptions, realtime helpers
```

### Request Flow

```text
Flutter UI
  -> Riverpod provider/notifier
  -> Flutter repository
  -> REST API or WebSocket
  -> DRF view / Channels consumer
  -> application service or command handler
  -> repository interface
  -> infrastructure repository / Django ORM
  -> MySQL / Redis / Cloudinary
  -> response DTO
  -> provider state
  -> UI render
```

### Event and Async Flow

```text
Business action
  -> database transaction
  -> append AuditLog
  -> Celery task dispatch
  -> notification fan-out / push / analytics aggregation
  -> WebSocket publish where needed
```

---

## API Overview

Base path:

```text
/api/v1/
```

Unprefixed REST routes such as `/plans/`, `/groups/`, and `/activities/`
are intentionally not exposed. Use the versioned `/api/v1/...` contract for
all REST clients.

Main REST resources:

| Feature | Endpoints |
|---------|-----------|
| Auth | `/o/token/`, `/api/v1/auth/logout/` |
| Users | `/api/v1/users/`, `/api/v1/users/profile/`, `/api/v1/users/verify-email/`, `/api/v1/users/resend-verification-email/` |
| Friends | `/api/v1/friends/`, `/api/v1/friends/request/`, `/api/v1/friends/requests/` |
| Groups | `/api/v1/groups/`, `/api/v1/groups/{id}/` |
| Plans | `/api/v1/plans/`, `/api/v1/plans/{id}/`, `/api/v1/plans/{id}/cancel/` |
| Availability | `/api/v1/groups/{group_id}/availability-polls/`, `/api/v1/availability-polls/{poll_id}/vote/` |
| Plan collaboration | `/api/v1/plans/{plan_id}/work-items/`, `/api/v1/plans/{plan_id}/comments/`, `/api/v1/plan-comments/{id}/react/`, `/api/v1/plan-comments/{id}/pin/` |
| Plan reuse/calendar | `/api/v1/plans/{plan_id}/clone/`, `/api/v1/plans/{plan_id}/export.ics`, `/api/v1/plans/{plan_id}/calendar-links/` |
| Activities | `/api/v1/activities/`, `/api/v1/activities/{id}/` |
| Conversations | `/api/v1/conversations/`, `/api/v1/conversations/{id}/send_message/` |
| Messages | `/api/v1/messages/` |
| Notifications | `/api/v1/notifications/`, `/api/v1/notifications/unread-count/`, `/api/v1/notifications/read-all/` |
| Notification preferences | `/api/v1/notifications/preferences/` |
| Group polls | `/api/v1/groups/{group_id}/polls/`, `/api/v1/group-polls/{poll_id}/vote/`, `/api/v1/group-polls/{poll_id}/close/` |
| Global search | `/api/v1/search/?q={query}` |
| Live location | `/api/v1/conversations/{conversation_id}/live-locations/`, `/api/v1/live-locations/{share_id}/` |
| Analytics | `/api/v1/analytics/summary/`, `/api/v1/analytics/timeseries/`, `/api/v1/analytics/top/` |
| Budget | `/api/v1/plans/{plan_id}/budget/`, `/api/v1/plans/{plan_id}/expenses/` |
| Audit Log | `/api/v1/audit-logs/`, `/api/v1/audit-logs/resource/{type}/{id}/` |
| Location | `/api/v1/location/reverse-geocode/`, `/api/v1/location/search/`, `/api/v1/location/autocomplete/`, `/api/v1/location/place-details/` |

WebSocket endpoints:

| Channel | Path |
|---------|------|
| Chat conversation | `/ws/chat/{conversation_id}/` |
| Plan collaboration | `/ws/plans/{plan_id}/` |
| Group updates | `/ws/groups/{group_id}/` |
| User private notifications | `/ws/user/` |
| System notifications | `/ws/notifications/` |

Swagger and Redoc are exposed in `DEBUG=True` or when `ENABLE_API_DOCS=True`.
Production can keep Django `DEBUG=False` and enable docs explicitly:

```text
/swagger/
/redoc/
```

For public demo docs set `API_DOCS_REQUIRE_AUTH=False`. For restricted
production docs set `API_DOCS_REQUIRE_AUTH=True` and sign in with an admin
account or provide a valid OAuth token.

---

## Build and Test

### Backend

```bash
cd planpalapp
..\.venv\Scripts\activate

python manage.py check
python manage.py makemigrations --check
python manage.py test
```

Focused regression examples:

```bash
python manage.py test planpals.tests.AuthEmailVerificationTests --noinput
python manage.py test planpals.analytics.tests --noinput
python manage.py test planpals.budgets.tests --noinput
python manage.py test planpals.notifications.tests --noinput
```

### Frontend

```bash
cd planpal_flutter
flutter analyze
flutter test
```

### Performance Testing

Locust performance scripts are stored in:

```text
performance_tests/
```

Run:

```bash
python -m locust -f performance_tests/locustfile.py --host=http://127.0.0.1:8000
```

Use the Locust UI to capture request count, failure rate, median latency, 95th percentile latency, and RPS for thesis/report evidence.

---

## Environment Setup

<details>
<summary><b>Backend local profile (planpalapp/.env.local)</b></summary>

```env
PLANPAL_ENV=local
SECRET_KEY=django-insecure-local-only
DEBUG=true
ALLOWED_HOSTS=10.0.2.2,localhost,127.0.0.1

# Database
DATABASE_URL=
DB_NAME=planpal
DB_USER=root
DB_PASSWORD=your_password
DB_HOST=localhost
DB_PORT=3306

# OAuth2 client used by Flutter
CLIENT_ID=your_oauth_client_id

# Redis / Celery / Channels
PLANPAL_USE_LOCAL_REDIS_DEFAULTS=true
REQUIRE_EXTERNAL_REDIS=false
CHANNEL_REDIS_SOCKET_TIMEOUT=15
CHANNEL_REDIS_CONNECT_TIMEOUT=5
CHANNEL_REDIS_HEALTH_CHECK_INTERVAL=30
USE_REDIS_CACHE=true
USE_REDIS_CHANNELS=true

# Email OTP verification
EMAIL_BACKEND=django.core.mail.backends.console.EmailBackend
EMAIL_HOST=smtp.gmail.com
EMAIL_PORT=587
EMAIL_USE_TLS=True
EMAIL_HOST_USER=
EMAIL_HOST_PASSWORD=
DEFAULT_FROM_EMAIL=PlanPal <noreply@planpal.local>

# Cloudinary
CLOUDINARY_CLOUD_NAME=your_cloud_name
CLOUDINARY_API_KEY=your_api_key
CLOUDINARY_API_SECRET=your_api_secret

# External APIs
GOONG_API_KEY=your_goong_or_location_api_key
BACKEND_PUBLIC_URL=http://127.0.0.1:8000

# Firebase / FCM
FIREBASE_SERVICE_ACCOUNT_PATH=
```

</details>

<details>
<summary><b>Frontend environment selector</b></summary>

Create `planpal_flutter/.env` from `planpal_flutter/.env.example` and set the
Goong map tile key. This client-side key renders vector maps only; place search
and reverse geocoding continue through the authenticated backend API.

```env
GOONG_MAPTILES_KEY=your_goong_maptiles_key
```

```powershell
# Android emulator -> local backend
flutter run --dart-define=APP_ENV=local

# Production backend
flutter run --release --dart-define=APP_ENV=production

# Physical phone -> local backend on the computer LAN address
flutter run --dart-define=APP_ENV=local `
  --dart-define=API_BASE_URL=http://192.168.1.10:8000
```

The Flutter `.env` asset remains only for existing Firebase/external-service
configuration. API URL and OAuth public client selection use build defines.

</details>

---

## Common Issues

| Problem | Cause | Solution |
|---------|-------|----------|
| Flutter emulator cannot reach backend | Android emulator does not use `localhost` for host machine | Use `http://10.0.2.2:8000` |
| Redis connection error | Redis container/service is not running | `docker run -d --name planpal-redis -p 6379:6379 redis:7` |
| `celery.exe` blocked on Windows | Application Control policy blocks direct executable | Use `python -m celery ...` |
| Email OTP not received | Dev email backend prints to console by default | Check backend terminal or configure SMTP credentials |
| Pending account disappears before verify | Pending registration lives in cache with TTL | Request a new OTP or register again |
| FCM `FIS_AUTH_ERROR` on emulator | Firebase project/package/API key mismatch or emulator service issue | Verify `google-services.json`, package name, SHA keys, and Google Play services |
| Map screen loads slowly on emulator | Emulator GPS/reverse geocode/network issue | Set emulator location, allow location permission, check backend location API key |
| WebSocket path returns 500 | Wrong WebSocket URL or missing token | Use `/ws/.../?token=<access_token>` with configured route |
| 403 on analytics | User lacks required permission/staff/admin access depending on endpoint policy | Use authorized account or adjust permission intentionally |

---

## Project Structure

```text
PlanPal/
├── AI_SYSTEM_DESIGN.md          # AI-optimized system architecture documentation
├── README.md                    # Project guide
├── Dockerfile                   # Backend container image
├── fly.toml                     # Fly.io deployment config
├── supervisord.conf             # Daphne + worker + singleton Beat process config
├── .github/workflows/           # CI, scheduled performance tests, deployment controls
├── performance_tests/           # Locust performance testing scripts
├── docs/                        # Architecture and deployment runbooks
├── scripts/                     # Operational backup utilities
├── planpalapp/                  # Django backend
│   ├── manage.py
│   ├── requirements.txt
│   ├── planpalapp/              # Settings, ASGI, URLs, Celery app
│   └── planpals/                # Bounded contexts
│       ├── auth/
│       ├── groups/
│       ├── plans/
│       ├── chat/
│       ├── budgets/
│       ├── audit/
│       ├── notifications/
│       ├── analytics/
│       ├── locations/
│       ├── integrations/
│       ├── shared/
│       └── migrations/
└── planpal_flutter/             # Flutter mobile application
    ├── pubspec.yaml
    ├── lib/
    │   ├── core/                # DTOs, repositories, providers, services, localization
    │   └── presentation/        # Pages and reusable widgets
    └── test/                    # Flutter widget/unit tests
```

Backend context convention:

```text
<context>/
├── domain/          # entities, events, enums, repository ports
├── application/     # services, command handlers, factories
├── infrastructure/  # Django models, ORM repositories, consumers, tasks
└── presentation/    # DRF views, serializers, permissions
```

Frontend convention:

```text
lib/
├── core/
│   ├── auth/
│   ├── dtos/
│   ├── localization/
│   ├── repositories/
│   ├── riverpod/
│   └── services/
└── presentation/
    ├── pages/
    └── widgets/
```

---

## Clean Architecture Rules

- Domain code must not depend on Django, DRF, Flutter, or infrastructure frameworks.
- Application services and command handlers contain business logic.
- Infrastructure repositories own ORM queries and persistence details.
- Presentation views and serializers adapt HTTP/WebSocket payloads only.
- Audit log remains append-only.
- Expensive work is moved to Celery when possible.
- Dashboard reads should use pre-aggregated analytics, not heavy request-time scans.
- Flutter widgets should call Riverpod providers/repositories, not raw API clients directly.

---

## Operational Notes

- Run Redis for realtime, Celery, cache, analytics, and pending OTP registration.
- Run Celery worker for notification delivery, push fan-out, plan lifecycle, cleanup, and analytics jobs.
- Run exactly one Celery Beat instance for scheduled aggregation and maintenance tasks.
- Keep the public OAuth `CLIENT_ID` synchronized between Django and the Flutter
  `OAUTH_CLIENT_ID` build define. Never bundle `CLIENT_SECRET` in Flutter.
- Do not commit real secrets, Firebase service accounts, Cloudinary secrets, or production database URLs.
- In production, set `DEBUG=False`, strict `ALLOWED_HOSTS`, strict CORS origins, SMTP credentials, managed database connection string, and password-authenticated TLS `rediss://` URLs.
- Configure `SENTRY_DSN` when centralized error tracking is available; sensitive request data is disabled.
- Schedule `scripts/backup_mysql.ps1` outside the application and verify restore procedures regularly.

---

## Author

**Nguyen Hoang Trieu Vy**  
GitHub: [@nhtrieuvy](https://github.com/nhtrieuvy)

<div align="center">

**Built with Flutter, Django, Channels, Celery, Redis, and MySQL**

[Back to Top](#planpal---collaborative-travel-planning-platform)

</div>
