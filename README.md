# 🌟 PlanPal - Travel Planning & Group Collaboration App

**PlanPal** là ứng dụng lập kế hoạch du lịch nhóm với tính năng chat real-time, quản lý hoạt động, và tích hợp bản đồ Việt Nam (Goong API).

## 📋 Mục Lục
- [Tổng Quan Hệ Thống](#tổng-quan-hệ-thống)
- [Yêu Cầu Hệ Thống](#yêu-cầu-hệ-thống)
- [Setup Backend (Django)](#setup-backend-django)
- [Setup Frontend (Flutter)](#setup-frontend-flutter)
- [Chạy Toàn Bộ Hệ Thống](#chạy-toàn-bộ-hệ-thống)
- [API Documentation](#api-documentation)
- [Troubleshooting](#troubleshooting)

---

## 🏗️ Tổng Quan Hệ Thống

### **Architecture Overview**
```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│  Flutter App    │────│  Django API     │────│     MySQL       │
│  (Mobile/Web)   │    │  (Backend)      │    │   (Database)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
    ┌─────────┐          ┌─────────────┐         ┌─────────────┐
    │Firebase │          │  Cloudinary │         │  Goong Maps │
    │   FCM   │          │   (Media)   │         │    API      │
    └─────────┘          └─────────────┘         └─────────────┘
```

### **Core Features**
- 👥 **User Management**: Authentication, profiles, friendships
- 🏢 **Group Management**: Create/join groups, admin roles
- 📅 **Plan Management**: Personal & group travel plans
- 💬 **Real-time Chat**: Group messaging with attachments
- 📍 **Location Services**: Vietnamese maps via Goong API
- 🔔 **Push Notifications**: Firebase Cloud Messaging
- 📱 **Cross-platform**: Android, iOS, Web support

---

## 🛠️ Yêu Cầu Hệ Thống

### **Backend Requirements**
- **Python**: 3.9+
- **Django**: 4.2+
- **MySQL**: 8.0+ (hoặc SQLite cho development)
- **Redis**: 6+ (cho caching - optional)

### **Frontend Requirements**
- **Flutter SDK**: 3.32+
- **Dart**: 3.0+
- **Android Studio**: 2024.3+ (cho Android development)
- **VS Code**: 1.80+ với Flutter extensions

### **External Services**
- **Cloudinary**: Image/file storage
- **Goong Maps API**: Vietnamese maps
- **Firebase**: Push notifications
- **MySQL**: Production database

---

## 🔧 Setup Backend (Django)

### **1. Clone Repository**
```bash
git clone https://github.com/trieuvyynXLe0/PlanPalApp.git
cd PlanPalApp
```

### **2. Setup Python Environment**
```bash
# Tạo virtual environment
python -m venv venv

# Activate virtual environment
# Windows:
venv\Scripts\activate
# macOS/Linux:
source venv/bin/activate

# Upgrade pip
python -m pip install --upgrade pip
```

### **3. Install Dependencies**
```bash
# Install Python packages
pip install -r requirements.txt
```

### **4. Database Setup**

#### **Option A: SQLite (Development)**
```bash
cd planpalapp

# Run migrations
python manage.py makemigrations
python manage.py migrate

# Create superuser
python manage.py createsuperuser
```

#### **Option B: MySQL (Production)**
```bash
# Install MySQL
# Windows: Download từ https://dev.mysql.com/downloads/mysql/
# macOS: brew install mysql
# Ubuntu: sudo apt-get install mysql-server

# Start MySQL service
# Windows: Services → MySQL80 → Start
# macOS: brew services start mysql
# Linux: sudo systemctl start mysql

# Create database
mysql -u root -p
CREATE DATABASE planpal_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'planpal_user'@'localhost' IDENTIFIED BY 'your_password';
GRANT ALL PRIVILEGES ON planpal_db.* TO 'planpal_user'@'localhost';
FLUSH PRIVILEGES;
EXIT;

# Update settings.py database config
# Xem section "Environment Variables" bên dưới
```

### **5. Environment Variables**
Tạo file `.env` trong thư mục `planpalapp/`:

```bash
# Database (MySQL)
DB_NAME=planpal_db
DB_USER=planpal_user
DB_PASSWORD=your_password
DB_HOST=localhost
DB_PORT=3306

# Django Settings
SECRET_KEY=your-super-secret-django-key-here
DEBUG=True
ALLOWED_HOSTS=localhost,127.0.0.1,0.0.0.0

# Cloudinary Settings
CLOUDINARY_CLOUD_NAME=your_cloud_name
CLOUDINARY_API_KEY=your_api_key
CLOUDINARY_API_SECRET=your_api_secret

# Goong Maps API
GOONG_API_KEY=your_goong_api_key

# Firebase Settings (for notifications)
FIREBASE_CREDENTIALS_PATH=../firebase-service-account.json
```

### **6. External Services Setup**

#### **Cloudinary Setup**
1. Tạo account tại [cloudinary.com](https://cloudinary.com)
2. Lấy `Cloud Name`, `API Key`, `API Secret`
3. Thêm vào `.env` file

#### **Goong Maps Setup**
1. Tạo account tại [docs.goong.io](https://docs.goong.io)
2. Tạo API key
3. Thêm vào `.env` file

#### **Firebase Setup (Optional)**
1. Tạo project tại [Firebase Console](https://console.firebase.google.com)
2. Download `service account key` → lưu vào `firebase-service-account.json`
3. Enable Cloud Messaging

### **7. Run Backend**
```bash
cd planpalapp

# Apply migrations
python manage.py migrate

# Collect static files (if needed)
python manage.py collectstatic --noinput

# Run development server
python manage.py runserver 0.0.0.0:8000
```

**Backend sẽ chạy tại: `http://localhost:8000`**

### **8. Test API**
```bash
# Test API endpoints
curl http://localhost:8000/api/
curl http://localhost:8000/api/users/

# Django Admin
# Truy cập: http://localhost:8000/admin/
# Login với superuser đã tạo
```

---

## 📱 Setup Frontend (Flutter)

### **1. Install Flutter SDK**

#### **Windows:**
```bash
# Download Flutter SDK
# https://docs.flutter.dev/get-started/install/windows

# Extract to C:\flutter
# Add to PATH: C:\flutter\bin

# Verify installation
flutter doctor
```

#### **macOS:**
```bash
# Using Homebrew
brew install flutter

# Or download manually
# https://docs.flutter.dev/get-started/install/macos
```

#### **Linux:**
```bash
# Download and extract Flutter
wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.32.8-stable.tar.xz
tar xf flutter_linux_3.32.8-stable.tar.xz

# Add to PATH
export PATH="$PATH:`pwd`/flutter/bin"
```

### **2. Setup Development Environment**

#### **Android Setup:**
```bash
# Install Android Studio
# https://developer.android.com/studio

# Install Android SDK command-line tools
# Android Studio → SDK Manager → SDK Tools → Command-line tools

# Accept licenses
flutter doctor --android-licenses
```

#### **VS Code Setup:**
```bash
# Install extensions:
# - Flutter (by Dart Code)
# - Dart (by Dart Code)
# - Android iOS Emulator
```

### **3. Verify Flutter Installation**
```bash
flutter doctor -v

# Expected output:
# [✓] Flutter (Channel stable, 3.32.8)
# [✓] Android toolchain 
# [✓] VS Code
# [✓] Connected device
```

### **4. Setup Project**
```bash
# Navigate to project directory
cd planpal_flutter

# Get dependencies
flutter pub get

# Generate code (if needed)
flutter packages pub run build_runner build
```

### **5. Configure API Endpoints**
Tạo file `lib/core/constants/api_constants.dart`:

```dart
class ApiConstants {
  // Thay YOUR_LOCAL_IP bằng IP thực của máy
  static const String baseUrl = 'http://YOUR_LOCAL_IP:8000/api';
  
  // Endpoints
  static const String login = '/auth/login/';
  static const String register = '/users/';
  static const String users = '/users/';
  static const String groups = '/groups/';
  static const String plans = '/plans/';
  static const String messages = '/messages/';
}
```

**Lấy Local IP:**
```bash
# Windows
ipconfig | findstr IPv4

# macOS/Linux  
ifconfig | grep inet
```

### **6. Setup Android Emulator**
```bash
# List available emulators
flutter emulators

# Create new emulator (if needed)
flutter emulators --create --name pixel_7

# Launch emulator
flutter emulators --launch pixel_7
```

### **7. Run Flutter App**
```bash
# Run on emulator
flutter run

# Or specify device
flutter run -d android
flutter run -d chrome  # for web testing

# Hot reload: Press 'r'
# Hot restart: Press 'R'
# Quit: Press 'q'
```

---

## 🚀 Chạy Toàn Bộ Hệ Thống

### **Step-by-step Startup Guide:**

#### **1. Start Backend**
```bash
# Terminal 1: Django Backend
cd planpalapp
python manage.py runserver 0.0.0.0:8000
```

#### **2. Start Android Emulator**
```bash
# Terminal 2: Android Emulator
flutter emulators --launch pixel_7
```

#### **3. Start Flutter App**
```bash
# Terminal 3: Flutter App
cd planpal_flutter
flutter run -d android
```

#### **4. Test Full System**
```bash
# Test API connection
curl http://localhost:8000/api/users/

# Test Flutter app - should show login screen
# Register new user → Login → Explore features
```

### **Development Workflow:**
1. **Backend changes**: Save file → Django auto-reloads
2. **Frontend changes**: Save file → Press `r` for hot reload
3. **Database changes**: `python manage.py makemigrations` → `python manage.py migrate`

---

## 📚 API Documentation

### **Authentication Endpoints**
```
POST /api/auth/login/          # Login user
POST /api/auth/logout/         # Logout user
POST /api/users/               # Register user
```

### **User Management**
```
GET    /api/users/profile/     # Get current user
PUT    /api/users/profile/     # Update profile
GET    /api/users/search/      # Search users
GET    /api/users/my_plans/    # Get user's plans
```

### **Group Management**
```
GET    /api/groups/            # List user's groups
POST   /api/groups/            # Create group
GET    /api/groups/{id}/       # Get group details
PUT    /api/groups/{id}/       # Update group
DELETE /api/groups/{id}/       # Delete group
POST   /api/groups/join/       # Join group
```

### **Plan Management**
```
GET    /api/plans/             # List user's plans
POST   /api/plans/             # Create plan
GET    /api/plans/{id}/        # Get plan details
PUT    /api/plans/{id}/        # Update plan
DELETE /api/plans/{id}/        # Delete plan
POST   /api/plans/{id}/add_activity/  # Add activity
```

### **Chat System**
```
GET    /api/messages/by_group/ # Get group messages
POST   /api/messages/          # Send message
PUT    /api/messages/{id}/     # Edit message
DELETE /api/messages/{id}/     # Delete message
```

### **Location Services**
```
GET    /api/places/search/     # Search places
GET    /api/places/nearby/     # Nearby places
GET    /api/geocode/           # Address ↔ Coordinates
```

**Full API Documentation:** Access Django admin hoặc setup Django REST Swagger

---

## 🔧 Troubleshooting

### **Common Backend Issues**

#### **Database Connection Error**
```bash
# Error: database "planpal_db" does not exist
# Solution:
mysql -u root -p
CREATE DATABASE planpal_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

#### **Missing Dependencies**
```bash
# Error: No module named 'cloudinary'
# Solution:
pip install -r requirements.txt
```

#### **Port Already in Use**
```bash
# Error: [Errno 10048] Only one usage... port 8000
# Solution:
python manage.py runserver 8001
# Or kill process using port 8000
```

### **Common Frontend Issues**

#### **Flutter Doctor Issues**
```bash
# Android license issue:
flutter doctor --android-licenses

# SDK not found:
flutter config --android-sdk /path/to/android/sdk
```
flutter emulators --launch Pixel_7
flutter run
#### **API Connection Issues**
```bash
# Error: Connection refused
# Solution: Check API_BASE_URL in Flutter app
# Use actual IP instead of localhost: http://192.168.1.100:8000
```

#### **Build Issues**
```bash
# Clean build
flutter clean
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
```

### **Network Issues**

#### **CORS Errors**
Trong Django `settings.py`:
```python
CORS_ALLOWED_ORIGINS = [
    "http://localhost:3000",
    "http://127.0.0.1:3000",
]
CORS_ALLOW_ALL_ORIGINS = True  # Only for development
```

#### **Firewall Issues**
```bash
# Windows: Allow Python/Flutter through Windows Firewall
# Ensure ports 8000, 3000 are accessible
```

---

## 🚀 Production Deployment

### **Backend Deployment (Django)**
- **Heroku/Railway**: Easy deployment
- **AWS/GCP**: Scalable options
- **VPS**: Cost-effective solution

### **Frontend Deployment (Flutter)**
- **Google Play Store**: Android distribution
- **Apple App Store**: iOS distribution  
- **Firebase Hosting**: Web version

### **Database**
- **Production**: MySQL on cloud
- **Development**: SQLite local

---

## 🤝 Contributing

1. Fork repository
2. Create feature branch: `git checkout -b feature/new-feature`
3. Commit changes: `git commit -m 'Add new feature'`
4. Push branch: `git push origin feature/new-feature`
5. Submit Pull Request

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 👨‍💻 Developer Info

- **Project**: PlanPal Travel Planning App
- **Backend**: Django REST Framework
- **Frontend**: Flutter
- **Database**: MySQL
- **APIs**: Goong Maps (Vietnam), Cloudinary, Firebase


