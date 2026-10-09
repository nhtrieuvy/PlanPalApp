# PlanPal System Design

Source of truth: the application code in this repository, inspected on 2026-10-07. This document describes implemented behavior, not a target architecture or the health of a live deployment. PlanPal currently has no AI/LLM runtime despite this document's historical filename.

## 1. System overview

PlanPal helps people plan trips together: create groups and plans, arrange activities, discuss locations, vote and coordinate availability, track work items, share expenses, and receive notifications. Regular users work in shared groups and conversations; staff users can access system analytics.

The client is one Flutter/Dart application built for Android and web, with platform-specific storage, push, map, and layout behavior. It calls a Django REST Framework API over HTTPS and uses Django Channels WebSockets for live chat, plan/group events, and notifications. Django persists relational data in MySQL. Redis backs production cache, Channels, and Celery messaging. Celery handles scheduled and asynchronous work. Goong, Cloudinary, Firebase, and SMTP are external integrations configured independently.

This is not a separate JavaScript web frontend and native mobile backend. Both clients share Flutter pages, repositories, DTOs, and business-facing flows, while adaptive navigation and selected platform services differ.

## 2. Repository and project structure

| Area | Role |
|---|---|
| planpal_flutter/lib/main.dart | Flutter startup, provider bootstrap, app router, theme and lifecycle setup. |
| planpal_flutter/lib/presentation/pages/ | Public site, authentication, and product pages. |
| planpal_flutter/lib/presentation/widgets/ | Shared controls, layouts, forms, and design-system widgets. |
| planpal_flutter/lib/core/ | Routing, responsive rules, Riverpod state, HTTP/WS clients, repositories, DTOs, auth, storage, maps, configuration, and utilities. |
| planpal_flutter/web/ | Web shell, bootstrap, Firebase messaging worker, manifest, and static metadata. |
| planpalapp/planpalapp/ | Django settings, root URLs, ASGI, Celery, and server configuration. |
| planpalapp/planpals/ | Domain contexts, API routes, consumers, middleware, health checks, and model facade. |
| planpalapp/planpals/migrations/ | Django schema migrations for the single app. |
| scripts/ | Local PowerShell runners and operational helpers. |
| Dockerfile, fly.toml, supervisord.conf | Backend image, Fly deployment, and multi-process runtime. |
| planpal_flutter/wrangler.jsonc | Cloudflare Worker static-asset deployment for the compiled web app. |

There is no generated shared schema package between Dart and Python. Client DTOs and server serializers are separate implementations of the HTTP contract. There is no AI-related source directory or AI provider adapter.

## 3. Frontend architecture

### Startup, routing, and layout

Flutter starts in planpal_flutter/lib/main.dart. It initializes persistent preferences and platform offline storage, restores authentication, sets up Riverpod providers, and launches MaterialApp.router. Navigation is defined in planpal_flutter/lib/core/routing/app_router.dart using go_router. Web exposes a public landing page at / and /welcome; the native root enters the authenticated flow or login. Product routes include /home, /groups, /groups/:id, /plans, /plans/:id, /conversations, /conversations/:id, /explore, /analytics, /notifications, and /profile. The router redirects unauthenticated visits to /login with a return path and restores the intended route after successful sign-in.

planpal_flutter/lib/presentation/widgets/layout/app_navigation_shell.dart supplies the authenticated shell: bottom navigation below 600 logical pixels, NavigationRail from 600 to 1024, and a sidebar above 1024. Breakpoints live in planpal_flutter/lib/core/responsive/app_breakpoints.dart. Public/authentication pages have their own composition; desktop is not simply a widened mobile screen.

Pages are grouped by feature under presentation/pages; core/theme and presentation/widgets/design_system hold visual tokens and reusable primitives. Several authenticated pages use deferred imports in app_router.dart to split web loading. Multi-step forms and feature-specific controls remain in presentation. The login/register transition is a UI-level change around the same auth operations, not a second auth mechanism.

### State and network

Riverpod providers under planpal_flutter/lib/core/riverpod wire repositories and feature notifiers for plans, groups, chat, finance, collaboration, experience, notifications, and analytics. Widgets invoke a notifier or repository, which uses the centralized Dio ApiClient in planpal_flutter/lib/core/services/apis.dart. API endpoints and base URL are centralized there; typed request/response objects are maintained manually under planpal_flutter/lib/core/dtos and feature repositories. There are no React hooks or browser-only frontend type definitions.

ApiClient sends JSON for ordinary operations and multipart data for uploads, including XFile/stream-based files so browser and mobile can use the same repository interfaces. AuthProvider attaches bearer tokens, retries a 401 once after refresh where supported, and clears the session when refresh cannot recover it. Error mapping and user-facing presentation are handled by core/services/api_error.dart and core/services/error_display_service.dart. Pages use Riverpod loading/error/data state, refresh actions, form validation, and localized messages rather than a single global loading screen.

Authentication and offline storage are distinct. OAuth access/refresh tokens are stored via flutter_secure_storage; a cached user profile is in SharedPreferences. On web, selected drafts and queued mutations use IndexedDB through core/storage/offline_storage_web.dart; on native platforms the offline store uses SharedPreferences. The queue in core/services/offline_sync_service.dart retries on a timer/resume and is scoped by user. It is not a full offline replica of server data.

MapLibre draws tiles from a Goong style URL using the client-side GOONG_MAPTILES_KEY. Place search and reverse geocoding call the backend location API, which has its own GOONG_API_KEY. WebSocket clients connect to chat, plan/group, and notification routes; browsers obtain a short-lived ticket first, while native clients retain the legacy token-query path. Optional Firebase Messaging registers browser/native device tokens for push, with a dedicated web service worker and VAPID configuration.

The build configuration in planpal_flutter/lib/config/app_config.dart reads dart-defines such as APP_ENV, API_BASE_URL, and OAUTH_CLIENT_ID. scripts/run_flutter.ps1 passes environment-specific defines for run/build commands; values in a local frontend .env are build inputs, not server-side secrets after web compilation.

## 4. Backend architecture

### Request and realtime pipeline

planpalapp/planpalapp/asgi.py is the production ASGI entry point: HTTP requests reach Django/DRF, while WebSockets are routed through Channels and token/ticket middleware. planpalapp/planpalapp/urls.py mounts /api/v1/ at planpalapp/planpals/urls.py, OAuth token routes under /o/, and health endpoints. The API URL file combines DRF router ViewSets with explicit class-based views. Default DRF authentication is OAuth2 bearer tokens and default permission is IsAuthenticated; individual public and admin endpoints override it.

The main contexts under planpalapp/planpals are auth, groups, plans, chat, collaboration, experience, budgets, locations, notifications, audit, and analytics. Most have presentation views/serializers, application services, and infrastructure repositories/models; some also have domain objects and repository interfaces. A typical mutation goes from URL/view to serializer validation and permission checks, then to an application service/handler, ORM repository or model, and finally a serializer response. This separation is useful but not absolute: some views and serializers also access ORM objects directly.

The planpals/models.py facade reexports context models so Django sees them under one installed app and migration tree. Auth, ownership, group/plan membership, and resource permissions are checked in the relevant views/services, not solely by frontend route guards. DRF serializers validate payloads; application services validate cross-record rules such as membership, budget currency, expense splits, and workflow state.

Channels routes are defined in planpalapp/planpals/routing.py for /ws/chat/{conversation_id}/, /ws/plans/{plan_id}/, /ws/groups/{group_id}/, /ws/user/, and /ws/notifications/. HTTP mutations publish realtime events after database commit where appropriate. The Celery app in planpalapp/planpalapp/celery.py discovers tasks; settings define queues and Beat jobs for metrics, cleanup, reminders, invites, recurring finance work, live-location expiry, and notification digests. Celery workers and Beat must actually run for scheduled behavior.

### Operations and integrations

Settings in planpalapp/planpalapp/settings.py select local, test, or production with PLANPAL_ENV. Local environment files may supply values; production requires explicit secrets and allowed hosts. DATABASE_URL or DB_* configures MySQL. Redis is used for production cache, Channels, and Celery (with component-specific URL overrides). Test settings use in-memory substitutes for selected services. Goong place queries are implemented in planpalapp/planpals/locations/infrastructure/goong_service.py. Cloudinary-backed media storage, Firebase Admin push, and SMTP mail are conditional on their configuration. WhiteNoise serves static files.

The backend has structured JSON logging, request correlation/X-Request-ID, a DRF exception handler, and liveness/readiness endpoints. Readiness checks infrastructure such as DB and Redis; it does not prove that every external provider or feature flow works. There is no AI provider, model invocation, prompt pipeline, or retrieval service in the backend.

## 5. Frontend-backend communication

Ordinary traffic follows:

User action -> Flutter page/widget -> Riverpod notifier/repository -> Dio ApiClient -> /api/v1/ route -> serializer/view -> service/repository -> MySQL or external service -> HTTP JSON/multipart response -> Dart DTO/state -> UI.

The exception is OAuth token issuance at /o/token/. Authenticated API requests send Authorization: Bearer {access token}. Responses are generally JSON; list endpoints can be paginated, so repositories handle the shapes of their respective routes. Uploads use multipart; calendar export returns an ICS file. HTTP errors are converted to client errors and shown as form or page feedback. A 401 may trigger refresh/retry; it is not treated as a successful empty result.

Representative implemented API groups (all below /api/v1/ unless noted):

| Group | Routes and purpose |
|---|---|
| Identity | /users/, /users/verify-email/, /users/profile/, /auth/logout/, /auth/websocket-ticket/; /o/token/ is mounted at root. |
| Social/trips | /friends/, /groups/, /plans/, /activities/ plus invite/join-request, clone, ICS, and calendar-link routes. |
| Coordination | /groups/{id}/polls/, /groups/{id}/availability-polls/, /plans/{id}/work-items/, /plans/{id}/comments/. |
| Chat/realtime | /conversations/, /conversations/{id}/send_message/, /messages/, /notifications/ and Channels /ws/... routes. |
| Finance | /plans/{id}/budget/, /expenses/, /balances/, /finance-insights/, /recurring-expenses/, /settlements/ and expense correction/detail routes. |
| Places/location | /location/search/, /location/autocomplete/, /location/place-details/, /location/reverse-geocode/, /conversations/{id}/live-locations/. |
| Administration | /analytics/summary/, /analytics/timeseries/, /analytics/top/ and /audit-logs/, with endpoint-specific permissions. |

The ViewSet action routes are generated by DRF router registrations and action decorators; not every route appears as a literal path in planpals/urls.py. Channels WebSockets provide realtime messages/events; push notifications use Firebase where configured. The client also polls/retries selected state and offline mutations. No SSE transport is present in the inspected code.

## 6. Data model and persistence

The default relational store is MySQL via Django ORM using DB_* variables; DATABASE_URL can override the database connection/engine. The schema lives in planpalapp/planpals/migrations/. Major models include:

| Context | Main persisted records and relationships |
|---|---|
| Identity/social | User, Friendship; Group with GroupMembership, invite, and join-request records. |
| Planning | Plan is personal or associated with a group and contains PlanActivity records; related work items, comments, mentions, and reactions support collaboration. |
| Messaging | Conversation and ChatMessage, with read-status records and membership/access checks. |
| Finance | Budget associated with a plan; Expense, ExpenseParticipant, ExpensePayment, Settlement, and RecurringExpense. Corrections create linked replacement expenses; effective expense queries exclude superseded entries from totals. |
| Coordination | AvailabilityPoll/option/vote and group poll/option/vote; LiveLocationShare for temporary sharing. |
| Operations | Notification, preference and device-token records; AuditLog; DailyMetric for aggregated analytics. |

The budget code validates currency against the plan budget rather than silently adding unmatched currency amounts. Financial corrections and deletion preserve historical/audit information rather than treating every update as an in-place overwrite. Redis-backed cache is used for transient state, WebSocket tickets, and selected cached reads, not as the source of truth for plans or expenses. Cloudinary stores uploaded media when configured. On-device/browser storage only holds session metadata and selected offline state.

## 7. Authentication and authorization

Registration starts with POST /api/v1/users/: the backend caches pending registration details and a hashed one-time code, then sends email. The user record is created after successful POST /api/v1/users/verify-email/ (the endpoint also handles verification of an existing inactive user). The pending registration is not a permanent inactive account by default. Login exchanges credentials and a public OAuth client ID at /o/token/ for access/refresh tokens; unverified accounts are rejected. OAuth Toolkit settings set token lifetimes and refresh rotation.

The Flutter AuthProvider restores its cached user and token on startup, refreshes the profile, and uses the access token in API requests. On logout it calls /api/v1/auth/logout/, clears secure tokens and cached profile, and removes user-scoped offline data. The go_router guard protects product pages and returns to the originally requested URL after login. Backend permissions remain authoritative even if a client navigates directly to an API or WebSocket.

Browser WebSockets request a cache-backed, single-use ticket with a short lifetime from /api/v1/auth/websocket-ticket/ before connection. Native clients can still connect with an access token in the query string for compatibility; this is a transitional contract, not proof that query tokens are safe for all environments. WebSocket consumers check identity and resource access. Admin analytics uses staff-only permission rather than just hiding the UI link.

## 8. AI / LLM status

No current AI/LLM application flow was found in Flutter or Django: no model-provider client, prompts, embeddings/vector store, RAG, tool calling, streaming model response, or AI-conversation persistence. The app's chat is human-to-human messaging. "Analytics" means computed usage/finance reports, not generative AI. This file's name is historical; any future AI feature would require a separate design and implementation. No AI API key is part of the observed runtime configuration.

## 9. Important end-to-end flows

### Sign-up and sign-in

The registration UI sends user details to /api/v1/users/, then the entered OTP to /api/v1/users/verify-email/. The backend holds pending details in cache, validates the OTP, creates/activates the user, and responds. Sign-in then posts to /o/token/; Flutter securely stores tokens, loads the profile, and navigates to the saved destination. Logout revokes/clears session state and scoped offline data.

### Create a plan

The plan form invokes a PlanRepository method and POST /api/v1/plans/. PlanViewSet validates payload and group permission, calls PlanService/CreatePlanHandler, persists the plan, initializes associated budget state, schedules relevant work, and returns serialized plan data. The repository parses the response and Riverpod updates the list/detail UI. Editing activities uses separate activity endpoints and permissions.

### Chat and attachment

The conversation page sends text or multipart attachment via ConversationRepository to /api/v1/conversations/{id}/send_message/. ConversationViewSet checks access and validates the payload; ConversationService persists the message and updates conversation state in a transaction. After commit, realtime and optional push notifications are dispatched. The sender receives HTTP state; other participants receive a WebSocket event. Historical messages are fetched through paginated endpoints, not reconstructed from WebSocket events alone.

### Expense and correction

The expense form sends plan, amount, payer, participants/splits, and optional receipt to /api/v1/plans/{id}/expenses/. BudgetService validates plan membership, currency, and shares, then creates the expense and related participant/payment records. Balance and insight reads aggregate effective expenses. Corrections use /expenses/{expense_id}/corrections/ to create a linked replacement; detail/delete operations use /expenses/{expense_id}/. Audit and notification work is attached to the backend flow.

### Map and live location

The Flutter map displays Goong tiles through MapLibre using a build-time map-tiles key. Search/geocoding calls /api/v1/location/... so the Goong service key stays on the backend. Conversation live location is created/read under /api/v1/conversations/{id}/live-locations/ and can be stopped through /api/v1/live-locations/{id}/; expiration requires the scheduled backend task. Browser geolocation additionally depends on user permission and browser support.

### Analytics and notifications

The analytics screen calls staff-protected /api/v1/analytics/summary/, /timeseries/, and /top/ actions. AnalyticsService serves summaries/time series from DailyMetric and reads top plans/groups from their repositories; Celery Beat refreshes daily metrics. Notifications are stored, listed via /api/v1/notifications/, and delivered over WebSocket/push where enabled. These paths do not rely on an AI inference service.

## 10. Configuration and environment

| Scope | Important names and behavior |
|---|---|
| Flutter build | scripts/run_flutter.ps1 passes APP_ENV and, when supplied, API_BASE_URL, OAUTH_CLIENT_ID, GOONG_MAPTILES_KEY, and FIREBASE_WEB_VAPID_KEY as dart-defines. Firebase runtime code also reads the optional PLANPAL_ENABLE_PUSH define, which the runner does not expose as a parameter. A web build embeds public client configuration; never put backend secrets there. |
| Django core | PLANPAL_ENV selects environment; SECRET_KEY, ALLOWED_HOSTS, CORS_ALLOWED_ORIGINS and related CSRF/security settings govern production exposure. Local files are loaded only as configured by settings.py. |
| Database/messaging | DATABASE_URL or DB_* for MySQL; REDIS_URL and/or cache/channel/Celery URL overrides for cache, Channels, and workers. Production settings require an external password-protected TLS Redis URL by default. |
| OAuth/email | OAuth Toolkit client configuration and SMTP variables support token issuance and verification emails. The Flutter OAuth client ID is public, unlike Django's SECRET_KEY. |
| External services | GOONG_API_KEY is backend-only; GOONG_MAPTILES_KEY is a browser-visible tile key. Cloudinary, Firebase service-account and web VAPID configuration, optional Sentry, and SMTP each need their respective credentials/settings. |

Example variable names and safe templates are in planpalapp/.env.example, planpalapp/.env.local.example, and planpal_flutter/.env.example. Values in those templates are not evidence that production services are configured or reachable.

## 11. Development and runtime architecture

Locally, scripts/run_backend.ps1 can run the Django web server, Celery worker, Beat, migrations, checks, or tests with the project's Python virtual environment. Django serves on port 8000 in the local setup; MySQL and Redis must be supplied separately for the corresponding features. scripts/run_flutter.ps1 runs Android or browser clients and builds APK or web artifacts. Local web uses 127.0.0.1:8000; an Android emulator uses 10.0.2.2:8000 to reach the host. CORS/allowed origins must match the browser origin; native requests do not use browser CORS.

For the configured backend deployment, Dockerfile builds the Python image, fly.toml defines the Fly app/service and migration release command, and supervisord.conf starts Daphne plus one Celery worker and Beat. A separate external MySQL/Redis and service secrets are required; a successful image build alone does not establish runtime readiness. /health/live and /health/ready serve liveness and dependency checks.

For web, Flutter produces planpal_flutter/build/web; planpal_flutter/wrangler.jsonc configures a Cloudflare Worker static-assets deployment with SPA fallback. The web directory contains metadata and a Firebase messaging worker. The presence of a web/_headers file does not by itself prove Cloudflare Workers applies those headers in production; verify actual responses when deploying. A production rebuild is needed when embedded dart-define values change.

## 12. Observed design decisions and patterns

- A single Flutter client shares feature flows while responsive shell and platform storage/push/maps adapt by target.
- go_router centralizes deep links and auth redirects; Riverpod provides feature state and repository construction.
- Dio is the central HTTP transport; Dart DTOs and DRF serializers implement a manually synchronized contract.
- Django contexts are feature-based with presentation/application/infrastructure separation in many paths, with domain abstractions where present.
- DRF ViewSets coexist with explicit APIViews; model facade and one migration tree keep Django model registration centralized.
- Services use transactions and post-commit realtime/push dispatch for operations such as chat; audit and notifications capture significant events.
- Celery/Beat provide asynchronous and scheduled behavior; Redis also supports cache and Channels fan-out.

These are observed patterns, not an assertion that every endpoint follows identical layering.

## 13. Current limitations and technical debt

- Dart DTOs/endpoints and Python serializers/routes are maintained separately; no generated OpenAPI client enforces compile-time parity.
- Backend layering is mixed: some presentation code still reaches ORM models directly, and ViewSet/action and standalone-view response shapes differ.
- Native WebSocket query-token authentication remains supported alongside the browser ticket flow.
- Offline support covers selected drafts/mutations, not all features or an authoritative synchronized local database.
- Optional Cloudinary, Goong, Firebase, email, Redis, and Cloudflare behavior depends on credentials, deployment settings, and reachable providers. Repository inspection cannot establish their current production health.
- Web CSP/cache behavior and browser-specific push/geolocation should be verified against the deployed Worker/browser, not inferred solely from checked-in configuration.

## 14. Architecture diagrams

~~~mermaid
flowchart LR
    U[Traveler or staff] --> F[Flutter Android or web]
    F --> R[Riverpod repositories and Dio]
    R -->|HTTPS JSON or multipart| A[Django DRF on Daphne]
    F -->|WebSocket ticket or native token| C[Django Channels]
    A --> M[(MySQL)]
    A --> X[(Redis cache)]
    C --> X
    A --> Q[Celery tasks]
    Q --> X
    Q --> M
    A --> G[Goong place API]
    A --> CL[Cloudinary media]
    A --> FB[Firebase push and SMTP]
    F -->|MapLibre tiles| GT[Goong tile service]
    F --> O[(IndexedDB web or native preferences)]
    W[Celery Beat] --> Q
~~~

~~~mermaid
sequenceDiagram
    actor User
    participant UI as Flutter conversation page
    participant Repo as ConversationRepository
    participant API as DRF ConversationViewSet
    participant Service as ConversationService
    participant DB as MySQL
    participant WS as Channels
    User->>UI: Send text or attachment
    UI->>Repo: sendMessage
    Repo->>API: POST /api/v1/conversations/{id}/send_message/
    API->>Service: validate access and create message
    Service->>DB: transaction: message and conversation state
    DB-->>Service: committed
    Service-->>WS: publish event after commit
    Service-->>API: saved message
    API-->>Repo: HTTP response
    Repo-->>UI: update state
    WS-->>UI: event for connected participants
~~~

## 15. File reference map

| Responsibility | Main files/directories |
|---|---|
| Flutter entry, build configuration | planpal_flutter/lib/main.dart; planpal_flutter/lib/config/app_config.dart; planpal_flutter/pubspec.yaml |
| Routing and adaptive shell | planpal_flutter/lib/core/routing/app_router.dart; planpal_flutter/lib/presentation/widgets/layout/app_navigation_shell.dart; planpal_flutter/lib/core/responsive/app_breakpoints.dart |
| Client transport, auth, state | planpal_flutter/lib/core/services/apis.dart; planpal_flutter/lib/core/auth/auth_session.dart; planpal_flutter/lib/core/riverpod/ |
| Client offline, maps, push | planpal_flutter/lib/core/services/offline_sync_service.dart; planpal_flutter/lib/core/storage/offline_storage_web.dart; planpal_flutter/lib/core/maps/planpal_map.dart; planpal_flutter/lib/core/services/firebase_service.dart |
| Django entry, routing, settings | planpalapp/planpalapp/asgi.py; planpalapp/planpalapp/urls.py; planpalapp/planpalapp/settings.py; planpalapp/planpals/urls.py; planpalapp/planpals/routing.py |
| Business services | planpalapp/planpals/plans/application/services.py; planpalapp/planpals/chat/application/services.py; planpalapp/planpals/budgets/application/services.py; planpalapp/planpals/analytics/application/services.py |
| Models and migrations | planpalapp/planpals/models.py; planpalapp/planpals/migrations/; planpalapp/planpals/budgets/infrastructure/models.py |
| Auth and WebSocket | planpalapp/planpals/auth/presentation/views.py; planpalapp/planpals/chat/presentation/views.py; planpalapp/planpals/routing.py |
| External integration | planpalapp/planpals/locations/infrastructure/goong_service.py; planpalapp/planpalapp/settings.py; planpal_flutter/web/firebase-messaging-sw.js |
| Background jobs and health | planpalapp/planpalapp/celery.py; planpalapp/planpals/shared/health.py |
| Local and production operations | scripts/run_backend.ps1; scripts/run_flutter.ps1; Dockerfile; fly.toml; supervisord.conf; planpal_flutter/wrangler.jsonc |
| AI integration | None implemented in the inspected application source. |
