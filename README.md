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


## NOTE: The app is NOT available from 09:00 PM to 07:00 AM. ⏲️

## Quick Start

### Backend Local Setup

```bash
git clone https://github.com/trieuvyynXLe0/PlanPalApp.git
cd PlanPalApp/planpalapp

python -m venv ..\.venv
..\.venv\Scripts\activate
pip install -r requirements.txt

python manage.py migrate
python manage.py runserver 0.0.0.0:8000
```

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
cd planpal_flutter
flutter pub get
flutter run --dart-define=PLANPAL_BASE_URL=http://10.0.2.2:8000
```

**Requirements:** Python 3.11+, Flutter 3.32+, Dart 3.8+, MySQL or compatible database, Redis 7+, Android Studio Emulator or physical Android device.

---

## Production Deploy

PlanPal is designed to run as stateless Django ASGI app + Celery worker + Redis-backed cache/channel layer. The current Docker image uses Supervisor to run Redis, Celery worker, Celery Beat, and Daphne in one container for simple deployment.

```bash
flyctl auth login
flyctl deploy -a planpal-backend
```

Check logs:

```bash
flyctl logs -a planpal-backend
```

Expected Supervisor programs:

- `redis`: local Redis process for cache, Channels, Celery broker in single-container deployment.
- `celery`: background worker for notifications, analytics, plan lifecycle, cleanup.
- `celery-beat`: periodic scheduler for analytics aggregation and maintenance jobs.
- `daphne`: ASGI server for REST API and WebSocket traffic.

For larger production deployments, Redis, database, web workers, and Celery workers should be separated into independent services.

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
| Maps/Location | Google Maps Flutter, Geolocator, backend location API |
| Charts | fl_chart |
| API Documentation | Swagger / Redoc via drf-yasg / OpenAPI |
| Deployment | Docker, Supervisor, Fly.io |

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

### Chat and Conversations

- Direct and group conversations.
- Text, image, file, audio/video attachment, and location messages.
- Cloudinary-backed media attachments.
- Read status and unread count.
- Chat WebSocket updates with reconnect behavior.
- Last message contract for conversation list.

### Map and Location

- Home map action opens current-location map screen.
- Device GPS support through Geolocator.
- Current location marker and coordinate display.
- Send current location to a selected conversation.
- Location picker with search, reverse geocoding, and place details API.

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

Main REST resources:

| Feature | Endpoints |
|---------|-----------|
| Auth | `/o/token/`, `/api/v1/auth/logout/` |
| Users | `/api/v1/users/`, `/api/v1/users/profile/`, `/api/v1/users/verify-email/`, `/api/v1/users/resend-verification-email/` |
| Friends | `/api/v1/friends/`, `/api/v1/friends/request/`, `/api/v1/friends/requests/` |
| Groups | `/api/v1/groups/`, `/api/v1/groups/{id}/` |
| Plans | `/api/v1/plans/`, `/api/v1/plans/{id}/`, `/api/v1/plans/{id}/cancel/` |
| Activities | `/api/v1/activities/`, `/api/v1/activities/{id}/` |
| Conversations | `/api/v1/conversations/`, `/api/v1/conversations/{id}/send_message/` |
| Messages | `/api/v1/messages/` |
| Notifications | `/api/v1/notifications/`, `/api/v1/notifications/unread-count/`, `/api/v1/notifications/read-all/` |
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

Swagger and Redoc are exposed in `DEBUG=True`:

```text
/swagger/
/redoc/
```

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
<summary><b>Backend .env (planpalapp/.env)</b></summary>

```env
SECRET_KEY=change-me
DEBUG=True
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
CLIENT_SECRET=your_oauth_client_secret

# Redis / Celery / Channels
CELERY_BROKER_URL=redis://127.0.0.1:6379/0
CELERY_RESULT_BACKEND=redis://127.0.0.1:6379/0
CACHE_REDIS_URL=redis://127.0.0.1:6379/1
CHANNEL_REDIS_URL=redis://127.0.0.1:6379/0
USE_REDIS_CACHE=True
USE_REDIS_CHANNELS=True

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
FIREBASE_CREDENTIALS_PATH=
```

</details>

<details>
<summary><b>Frontend .env (planpal_flutter/.env)</b></summary>

```env
BASE_URL=http://10.0.2.2:8000
PLANPAL_BASE_URL=http://10.0.2.2:8000
CLIENT_ID=your_oauth_client_id
CLIENT_SECRET=your_oauth_client_secret
GOONG_API_KEY=your_goong_or_location_api_key
```

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
├── supervisord.conf             # Redis + Celery + Beat + Daphne process config
├── performance_tests/           # Locust performance testing scripts
├── docs/                        # Additional report/documentation assets
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
- Run Celery Beat for scheduled aggregation and maintenance tasks.
- Keep `CLIENT_ID` and `CLIENT_SECRET` synchronized between backend OAuth application and Flutter `.env`.
- Do not commit real secrets, Firebase service accounts, Cloudinary secrets, or production database URLs.
- In production, set `DEBUG=False`, strict `ALLOWED_HOSTS`, strict CORS origins, SMTP credentials, Redis URLs, and managed database connection string.

---

## Author

**Nguyen Hoang Trieu Vy**  
GitHub: [@nhtrieuvy](https://github.com/nhtrieuvy)

<div align="center">

**Built with Flutter, Django, Channels, Celery, Redis, and MySQL**

[Back to Top](#planpal---collaborative-travel-planning-platform)

</div>
