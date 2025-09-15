# 🌟 PlanPal - Collaborative Travel Planning Platform


**PlanPal** is a comprehensive travel planning application designed for seamless group collaboration. It features real-time chat, activity management, and dynamic map integration, providing a one-stop solution for organizing trips.

---

## 🏗️ System Architecture

PlanPal is built on a robust client-server architecture, ensuring scalability and maintainability.

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Flutter App    │◀───▶│  Django REST    │◀───▶│     MySQL       │
│  (Mobile/Web)   │    │    Framework    │    │   (Database)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
    ┌─────────┐          ┌─────────────┐         ┌─────────────┐
    │Firebase │          │  Cloudinary │         │  Goong Maps │
    │   FCM   │          │(Media Storage)│         │ (Location API)│
    └─────────┘          └─────────────┘         └─────────────┘
```

- **Frontend**: A cross-platform application built with Flutter, supporting Android, iOS, and Web.
- **Backend**: A powerful API powered by Django REST Framework, handling all business logic.
- **Database**: MySQL is used for production data storage, offering reliability and performance.
- **External Services**:
    - **Cloudinary**: Manages all media assets, including user avatars and message attachments.
    - **Goong Maps API**: Provides Vietnam-specific location services, including search, geocoding, and nearby places.
    - **Firebase**: Handles real-time push notifications via Firebase Cloud Messaging (FCM).

---

## ✨ Core Features

### Backend (Django REST Framework)

- **Authentication & Authorization**:
  - Secure OAuth2-style authentication with access and refresh tokens.
  - Permission-based access control to protect API endpoints.
- **User & Social**:
  - Complete user profiles with avatars (hosted on Cloudinary), bios, and contact information.
  - Friendship management system (send, accept, reject invitations).
  - Real-time counts for unread messages and notifications.
- **Group Management**:
  - Full CRUD functionality for groups with distinct roles (admin, member).
  - Secure group joining via invite codes or direct IDs.
  - Endpoints to list group members, administrators, and recent messages.
- **Plan Management**:
  - Supports both private (personal) and collaborative (group) travel plans.
  - Comprehensive plan details: title, description, start/end dates, and public/private visibility.
  - Automated plan status calculation (e.g., Upcoming, Ongoing, Completed).
  - Business logic to ensure only group members can create or modify group plans.
- **Activity & Itinerary**:
  - Add, update, and delete plan activities with specified times, locations, and estimated costs.
  - Built-in validation to prevent overlapping activity schedules within the same plan.
- **Real-time Messaging**:
  - Group-specific chat rooms for seamless communication.
  - Support for rich media attachments (images, files) via Cloudinary.
  - Location sharing within messages, including latitude/longitude and place names.

### Frontend (Flutter)

- **Authentication & Profile**:
  - Intuitive screens for user login, registration, and password recovery.
  - A dedicated section for users to view and update their personal profiles.
- **Plan Management**:
  - Clean and organized lists for viewing personal and group plans.
  - User-friendly forms for creating, editing, and deleting plans with clear type selection (Personal/Group).
  - Robust input validation to ensure data integrity (e.g., title length, valid date ranges).
  - Informative UI components like badges for plan types, status chips, and date displays.
- **Group Interaction**:
  - Detailed views for group information, member lists, and administrative controls.
  - Simple and effective interface for creating and managing groups.
- **User Experience**:
  - A modern, consistent, and responsive user interface.
  - Centralized error handling to provide clear and helpful feedback to the user.
  - Cross-platform compatibility for a native experience on Android, iOS, and the Web.

---

## 🛠️ Tech Stack

| Category      | Technology                                       |
|---------------|--------------------------------------------------|
| **Backend**   | Python, Django, Django REST Framework            |
| **Frontend**  | Flutter, Dart                                    |
| **Database**  | MySQL (Production), SQLite (Development)         |
| **Cache**     | Redis (Optional)                                 |
| **Media**     | Cloudinary                                       |
| **Maps**      | Goong Maps API                                   |
| **Notifications**| Firebase Cloud Messaging (FCM)                |

---

## 🚀 Getting Started

Follow these instructions to set up the project for local development.

### 📋 Prerequisites

- **Python**: 3.9+
- **Flutter SDK**: 3.32+
- **Database**: MySQL 8.0+

### 🔧 Backend Setup (Django)

1.  **Clone the Repository**:
    ```bash
    git clone https://github.com/trieuvyynXLe0/PlanPalApp.git
    cd PlanPalApp/planpalapp
    ```

2.  **Create a Virtual Environment**:
    ```bash
    # Windows
    python -m venv venv
    venv\Scripts\activate

    # macOS/Linux
    python3 -m venv venv
    source venv/bin/activate
    ```

3.  **Install Dependencies**:
    ```bash
    pip install -r requirements.txt
    ```

4.  **Configure Environment Variables**:
    Create a `.env` file in the `planpalapp/` directory and add the following configuration.
    
    ```env
    # Django Settings
    SECRET_KEY=your-super-secret-django-key
    DEBUG=True
    ALLOWED_HOSTS=localhost,127.0.0.1

    # Database (Example for MySQL)
    DB_NAME=planpal_db
    DB_USER=planpal_user
    DB_PASSWORD=your_password
    DB_HOST=localhost
    DB_PORT=3306

    # External Services
    CLOUDINARY_CLOUD_NAME=your_cloud_name
    CLOUDINARY_API_KEY=your_api_key
    CLOUDINARY_API_SECRET=your_api_secret
    GOONG_API_KEY=your_goong_api_key
    FIREBASE_CREDENTIALS_PATH=../firebase-service-account.json
    ```

5.  **Run Database Migrations**:
    ```bash
    python manage.py makemigrations
    python manage.py migrate
    ```

6.  **Create a Superuser**:
    ```bash
    python manage.py createsuperuser
    ```

7.  **Run the Development Server**:
    ```bash
    python manage.py runserver
    ```
    The backend will be available at `http://127.0.0.1:8000`.

### ⚙️ Redis & Celery (Windows)

PlanPal uses Redis as the Celery broker and for caching. On Windows you can run Redis via WSL2, a native Windows port (e.g., Chocolatey), or run Redis on another machine.

Quick notes:
- For development, WSL2 (Ubuntu) is recommended because the official Redis build targets Linux.
- If you use a native Windows build (Chocolatey), add `redis-server` to PATH or install as a service.

Start Redis (WSL recommended):

```powershell
# If using WSL2 (preferred):
wsl -d Ubuntu -- bash -ic "redis-server --protected-mode no"

# If redis-server is on PATH natively:
redis-server

# If installed via Chocolatey as a service:
Start-Service redis
```

Start Celery worker (from `planpalapp/` and with virtualenv activated):

```powershell
# Activate virtualenv
venv\Scripts\Activate

# Start Celery worker
celery -A planpalapp worker --loglevel=info
```

### 📱 Frontend Setup (Flutter)

1.  **Navigate to the Frontend Directory**:
    ```bash
    cd ../planpal_flutter
    ```

2.  **Install Dependencies**:
    ```bash
    flutter pub get
    ```

3.  **Configure API Endpoint**:
    Create a file at `lib/core/services/apis.dart` and define your backend URL.
    *(Ensure you use your local network IP address, not `localhost`, when running on a physical device.)*
    ```dart
    const String baseUrl = 'http://localhost:8000';
    ```

4.  **Run Android emulator (if required)**:
    Here I use android studio
    *(Ensure you have an emulator device in the emulator software)
    ```bash
    flutter emulator --launch name_device
    ```

5.  **Run the App**:
    ```bash
    # Select a device (e.g., Chrome, an Android emulator, or a physical device)
    flutter run
    ```

### 🌐 Running the Full System

1.  **Start the Backend Server**:
    Open a terminal, navigate to `planpalapp/`, and run `python manage.py runserver`.

2.  **Start the Frontend Application**:
    Open a second terminal, navigate to `planpal_flutter/`, and run `flutter run` after selecting a target device.

---

## 📚 API Documentation

The API is self-documented using the browsable API feature of Django REST Framework. Once the backend server is running, you can explore the available endpoints by navigating to `http://127.0.0.1:8000/api/`.

Key endpoints include:
- `/api/auth/`: Authentication (login, logout).
- `/api/users/`: User management and profiles.
- `/api/groups/`: Group creation and management.
- `/api/plans/`: Travel plan operations.
- `/api/messages/`: Real-time chat messages.

---

## 📄 Author
Author: Nguyen Hoang Trieu Vy - [@nhtrieuvy](https://github.com/nhtrieuvy)


