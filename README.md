# 🌟 PlanPal - Travel Planning Platform

[![Flutter](https://img.shields.io/badge/Flutter-3.32+-02569B?logo=flutter)](https://flutter.dev/)
[![Django](https://img.shields.io/badge/Django-5.2+-092E20?logo=django)](https://www.djangoproject.com/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> 🗺️ A collaborative travel planning app with real-time chat, activity management, and map integration.

## 📲 Try It Now

| Platform | Link |
|----------|------|
| 📱 **Android APK** | [Download v1.0.0](https://github.com/trieuvyynXLe0/PlanPalApp/releases/latest) *(55MB)* |
| 🌐 **Live API** | [planpal-backend.fly.dev](https://planpal-backend.fly.dev/swagger) |
| 🔧 **Admin Panel** | [Admin Login](https://planpal-backend.fly.dev/admin) |

---

## ⚡ Quick Start

### 🔹 For Developers (Local Setup)

**Backend (Django)**
```bash
git clone https://github.com/trieuvyynXLe0/PlanPalApp.git
cd PlanPalApp/planpalapp
python -m venv venv && venv\Scripts\activate
pip install -r requirements.txt
python manage.py migrate && python manage.py runserver
```

**Frontend (Flutter)**
```bash
cd planpal_flutter
flutter pub get && flutter run
```

**📋 Requirements:** Python 3.11+, Flutter 3.32+, Redis (optional for dev)

### 🔹 For Production (Fly.io)

```powershell
flyctl auth login
flyctl deploy -a planpal-backend        # Deploy backend
flyctl deploy -a planpal-worker --config fly.worker.toml  # Deploy worker
```

**📋 Requirements:** Fly CLI, MySQL (Aiven), Redis service

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|------------|
| 📱 **Mobile** | Flutter, Dart |
| 🔧 **Backend** | Django REST, Python |
| 💾 **Database** | MySQL (Prod), SQLite (Dev) |
| 🔄 **Cache/Queue** | Redis, Celery |
| ☁️ **Cloud** | Fly.io, Cloudinary |
| 🗺️ **Maps** | Goong Maps API |
| 📬 **Notifications** | Firebase FCM |

---

## ✨ Key Features

### 🔐 Authentication
- OAuth2 token-based auth
- User profiles with avatars

### 👥 Social
- Friend management
- Real-time notifications

### 📅 Plans
- Personal & group travel plans
- Activity scheduling with conflict detection

### 💬 Chat
- Group messaging
- Media attachments

---

## 📦 Build & Deploy

## 📦 Build & Deploy

### 📱 Android APK
```bash
cd planpal_flutter
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
```

### 🚀 Production Deploy
```bash
flyctl deploy -a planpal-backend  # Backend
flyctl deploy -a planpal-worker --config fly.worker.toml  # Worker
```

---

## 📚 API Endpoints

| Endpoint | Description |
|----------|-------------|
| `POST /api/token/` | Get access token |
| `GET /api/users/me/` | Current user profile |
| `GET /api/plans/` | List travel plans |
| `GET /api/groups/` | List groups |
| `GET /api/conversations/` | List chats |

**Full docs**: [planpal-backend.fly.dev/api](https://planpal-backend.fly.dev/api)

---

## 🔧 Environment Setup

<details>
<summary><b>Backend .env (planpalapp/.env)</b></summary>

```env
SECRET_KEY=your-secret-key
DEBUG=True
DATABASE_URL=sqlite:///db.sqlite3
REDIS_HOST=localhost
CLIENT_ID=oauth_client_id
CLIENT_SECRET=oauth_secret
CLOUDINARY_CLOUD_NAME=your_cloud
CLOUDINARY_API_KEY=your_key
GOONG_API_KEY=your_goong_key
```
</details>

<details>
<summary><b>Frontend .env (planpal_flutter/.env)</b></summary>

```env
BASE_URL=http://10.0.2.2:8000
CLIENT_ID=oauth_client_id
CLIENT_SECRET=oauth_secret
GOONG_API_KEY=your_goong_key
```
</details>

---

## 🐛 Common Issues

| Problem | Solution |
|---------|----------|
| ❌ Redis connection failed | `wsl -d Ubuntu -- redis-server` or `Start-Service redis` |
| ❌ Flutter network error (emulator) | Use `BASE_URL=http://10.0.2.2:8000` in `.env` |
| ❌ Celery worker SIGKILL | Use `--pool=solo` or scale memory |
| ❌ Fly deploy fails | Check `flyctl logs -a <app>` and secrets |

---

## 📂 Project Structure

```
PlanPalApp/
├── planpalapp/           # Django backend
│   ├── planpals/        # Main app (models, views, serializers)
│   ├── planpalapp/      # Settings, URLs, Celery config
│   └── requirements.txt
├── planpal_flutter/     # Flutter frontend
│   ├── lib/
│   │   ├── core/       # DTOs, providers, repos
│   │   └── presentation/ # Pages, widgets
│   └── pubspec.yaml
├── Dockerfile           # Backend container
├── Dockerfile.worker    # Worker container
├── fly.toml            # Backend Fly config
└── fly.worker.toml     # Worker Fly config
```

---

## 👤 Author

**Nguyen Hoang Trieu Vy**  
GitHub: [@nhtrieuvy](https://github.com/nhtrieuvy)

---

## 📜 License

MIT License - see [LICENSE](LICENSE) file

---

<div align="center">

**Made with ❤️ using Flutter & Django**

[⬆ Back to Top](#-planpal---travel-planning-platform)

</div>


