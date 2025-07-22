# PlanPal Services Documentation

## Tổng quan

Services layer được thiết kế để tách biệt business logic và tích hợp external APIs khỏi Django views. Điều này giúp code dễ maintain, test và reuse.

## Kiến trúc Services

### 1. BaseService

**File:** `planpals/services/base_service.py`

Lớp abstract cung cấp functionality cơ bản cho tất cả services:
- Logging system
- Error handling 
- Configuration validation

```python
from planpals.services import BaseService

class MyService(BaseService):
    def validate_config(self) -> bool:
        # Implement validation logic
        return True
```

### 2. GooglePlacesService

**File:** `planpals/services/google_places_service.py`

Service tích hợp với Google Places API để tìm kiếm và lấy thông tin địa điểm.

#### Các phương thức chính:

**search_places(query, location, radius, place_type)**
- Tìm kiếm địa điểm theo từ khóa
- Có thể giới hạn trong bán kính nhất định
- Hỗ trợ filter theo loại địa điểm

```python
from planpals.services import google_places_service

# Tìm kiếm nhà hàng ở Hà Nội
places = google_places_service.search_places(
    query="nhà hàng ngon",
    location=(21.0285, 105.8542),  # Hà Nội
    radius=5000,
    place_type="restaurant"
)
```

**get_place_details(place_id, fields)**
- Lấy thông tin chi tiết của một địa điểm
- Có thể chọn các fields cần lấy để tối ưu performance

```python
details = google_places_service.get_place_details(
    place_id="ChIJN1t_tDeuEmsRUsoyG83frY4",
    fields=['name', 'rating', 'reviews', 'photos']
)
```

**get_nearby_places(lat, lng, radius, place_type)**
- Lấy danh sách địa điểm xung quanh một tọa độ
- Phù hợp cho tính năng "places nearby"

### 3. NotificationService

**File:** `planpals/services/notification_service.py`

Service xử lý push notifications và email notifications.

#### Push Notifications:

**send_push_notification(fcm_tokens, title, body, data)**
- Gửi notification đến nhiều device cùng lúc
- Hỗ trợ custom data payload

```python
from planpals.services import notification_service

success = notification_service.send_push_notification(
    fcm_tokens=['token1', 'token2'],
    title="Tin nhắn mới",
    body="Bạn có tin nhắn mới trong nhóm ABC",
    data={'type': 'new_message', 'group_id': '123'}
)
```

**send_group_notification(group_id, title, body, exclude_user_id)**
- Gửi notification cho tất cả thành viên trong group
- Có thể loại trừ một user (thường là người gửi)

**notify_new_message(group_id, sender_name, message_preview, sender_id)**
- Helper method cho notification tin nhắn mới
- Tự động format title/body và exclude sender

#### Email Notifications:

**send_email_notification(to_emails, subject, template_name, context)**
- Gửi email từ template HTML
- Hỗ trợ cả plain text và HTML format

## Sử dụng Services trong Views

### API Endpoints với Services

**1. Places Search API**
```
GET /api/places/search/?query=restaurant&lat=21.0285&lng=105.8542&radius=1000&type=restaurant
```

**2. Place Details API**
```
GET /api/places/{place_id}/details/
```

**3. Nearby Places API**
```
GET /api/places/nearby/?lat=21.0285&lng=105.8542&radius=1000&type=tourist_attraction
```

### Enhanced ViewSets

**EnhancedGroupViewSet**
- Kế thừa từ GroupViewSet
- Tự động gửi notification khi có tin nhắn mới

**EnhancedPlanViewSet**
- Tích hợp Google Places khi thêm activity
- Tự động gửi notification khi plan được update

## Configuration

### Environment Variables

```bash
# Google Places API
GOOGLE_PLACES_API_KEY=your-api-key

# Firebase Cloud Messaging  
FCM_SERVER_KEY=your-fcm-server-key

# Email settings
EMAIL_HOST=smtp.gmail.com
EMAIL_HOST_USER=your-email@gmail.com
EMAIL_HOST_PASSWORD=your-app-password
```

### Settings.py

```python
# External API Keys
GOOGLE_PLACES_API_KEY = os.getenv('GOOGLE_PLACES_API_KEY')
FCM_SERVER_KEY = os.getenv('FCM_SERVER_KEY')

# Logging cho services
LOGGING = {
    'loggers': {
        'planpals.services': {
            'handlers': ['console', 'file'],
            'level': 'DEBUG',
            'propagate': False,
        },
    },
}
```

## Installation

1. **Install dependencies**
```bash
pip install googlemaps==4.10.0
```

2. **Setup API keys**
- Tạo file `.env` từ `.env.example`
- Điền các API keys cần thiết

3. **Configure logging directory**
```bash
mkdir planpalapp/logs
```

## Testing Services

### Unit Testing

```python
from django.test import TestCase
from planpals.services import google_places_service

class GooglePlacesServiceTest(TestCase):
    def test_search_places(self):
        places = google_places_service.search_places("restaurant")
        self.assertIsInstance(places, list)
```

### Manual Testing

```python
# Test trong Django shell
python manage.py shell

from planpals.services import google_places_service, notification_service

# Test Places API
places = google_places_service.search_places("Hà Nội")
print(places)

# Test Notifications
notification_service.send_push_notification(
    fcm_tokens=['test-token'],
    title="Test",
    body="This is a test notification"
)
```

## Error Handling

Services sử dụng comprehensive logging và error handling:

```python
# Logs được ghi vào planpalapp/logs/planpal.log
# Console logs hiển thị trong development

# Example log output:
INFO 2024-01-20 10:30:45 google_places_service Tìm được 5 địa điểm cho 'restaurant'
ERROR 2024-01-20 10:31:12 notification_service FCM error cho token abcd1234...: Invalid registration token
```

## Best Practices

1. **Sử dụng service instances từ __init__.py**
```python
from planpals.services import google_places_service, notification_service
```

2. **Kiểm tra config trước khi sử dụng**
```python
if not google_places_service.validate_config():
    return Response({'error': 'Google Places not configured'})
```

3. **Handle exceptions gracefully**
```python
try:
    places = google_places_service.search_places(query)
except Exception as e:
    logger.error(f"Places search failed: {e}")
    return Response({'error': 'Search temporarily unavailable'})
```

4. **Sử dụng background tasks cho notifications**
```python
# Trong production, nên sử dụng Celery cho notification tasks
from celery import shared_task

@shared_task
def send_group_notification_async(group_id, title, body):
    notification_service.send_group_notification(group_id, title, body)
```

## Future Enhancements

1. **WeatherService** - Tích hợp weather API
2. **TranslationService** - Đa ngôn ngữ
3. **AnalyticsService** - Tracking user behavior  
4. **PaymentService** - Tích hợp thanh toán
5. **BackupService** - Backup dữ liệu người dùng
