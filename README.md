# 🌟 PlanPal - Travel Planning Platform

[![Flutter](https://img.shields.io/badge/Flutter-3.32+-02569B?logo=flutter)](https://flutter.dev/)
[![Django](https://img.shields.io/badge/Django-5.2+-092E20?logo=django)](https://www.djangoproject.com/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> 🗺️ A collaborative travel planning app with real-time chat, activity management, and map integration.

## 📲 Try It Now

| Platform | Link |
|----------|------|
| 📱 **Android APK** | [Download v1.0.0](https://github.com/trieuvyynXLe0/PlanPalApp/releases/latest) *(55MB)* |
| 🌐 **Live API** | [planpal-backend.fly.dev/swagger](https://planpal-backend.fly.dev/swagger) |
| 🔧 **Admin Panel** | [Admin Login](https://planpal-backend.fly.dev/admin) |

---
## Demo Account:
**Account 1 (Admin Account):**
username: admin |
password: 123
(You can login the Admin Panel)

**Account 2:**
username: u1 |
password: 12345678

**Account 3:**
username: u2 |
password: 12345678

---
## NOTE: The app is NOT available between 09:00 PM and 07:00 AM. ⏲️
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

```bash
flyctl auth login
flyctl deploy -a planpal-backend  # Deploy tất cả: Redis + Backend + Worker
```

**📋 Requirements:** Fly CLI, MySQL (Aiven), Cloudinary

---

## 🛠️ Tech Stack

| Layer | Technology |
|-------|------------|
| 📱 **Mobile** | Flutter, Dart |
| 🔧 **Backend** | Django REST, Python |
| 💾 **Database** | MySQL (Prod)|
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
- Chat realtime
---

## 📦 Build & Deploy

### 📱 Android APK
```bash
cd planpal_flutter
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
```

### 🚀 Production Deploy

```bash
flyctl deploy -a planpal-backend
```

**Kiểm tra logs:**
```bash
flyctl logs -a planpal-backend
```

Bạn sẽ thấy output của cả 3 services:
- `[program:redis]` - Redis server (local)
- `[program:celery]` - Celery worker
- `[program:daphne]` - Web server (Django)

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
| ❌ Redis connection failed (local dev) | `wsl -d Ubuntu -- redis-server` or `Start-Service redis` |
| ❌ Flutter network error (emulator) | Use `BASE_URL=http://10.0.2.2:8000` in `.env` |
| ❌ Fly deploy fails | Check `flyctl logs -a planpal-backend` and secrets |
| ❌ Out of memory on Fly | Scale RAM: `flyctl scale memory 1024 -a planpal-backend` |

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
├── Dockerfile           # Container cho cả Redis + Backend + Worker
└── fly.toml            # Fly.io config (1 máy duy nhất)
```
python -m celery -A planpalapp worker -l info --pool=solo -Q high_priority,default,plan_status,low_priority
python -m celery -A planpalapp beat -l info
---

## 👤 Author

**Nguyen Hoang Trieu Vy**  
GitHub: [@nhtrieuvy](https://github.com/nhtrieuvy)


<div align="center">

**Made with using Flutter & Django**

**Thanks for taking the time to read ❤️**

[⬆ Back to Top](#-planpal---travel-planning-platform)

</div>


