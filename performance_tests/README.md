# PlanPal Performance Testing Guide

Mục tiêu của bộ test này là tạo màn hình kết quả đo hiệu năng API để chụp lại và chèn vào báo cáo.

Locust cung cấp UI tại `http://localhost:8089` với các bảng:

- `Statistics`: Avg, Min, Max, Median, P95/P99, Failures.
- `Charts`: biểu đồ response time, RPS, user count.
- `Failures`: lỗi API nếu có.

## 1. Cài dependency

Chạy trong PowerShell tại thư mục project:

```powershell
cd D:\Study\DoAnNganh\PlanPal
.\.venv\Scripts\activate
.\.venv\Scripts\python.exe -m pip install -r .\performance_tests\requirements-performance.txt
```

Nếu máy chặn `pip.exe` hoặc `locust.exe` bằng Application Control, luôn chạy qua module Python như trên:

```powershell
.\.venv\Scripts\python.exe -m pip --version
.\.venv\Scripts\python.exe -m locust --version
```

## 2. Chuẩn bị hệ thống trước khi test

Mở Redis:

```powershell
docker start planpal-redis
```

Chạy backend:

```powershell
cd D:\Study\DoAnNganh\PlanPal\planpalapp
python manage.py runserver 0.0.0.0:8000
```

Nếu muốn đo các tác vụ nền notification/analytics sát thực tế hơn, mở thêm Celery bằng module Python để tránh lỗi Windows chặn `celery.exe`:

```powershell
cd D:\Study\DoAnNganh\PlanPal\planpalapp
python -m celery -A planpalapp worker -l info --pool=solo -Q high_priority,default,plan_status,low_priority
```

## 3. Chuẩn bị tài khoản test

Tài khoản test nên có:

- Đã verify email nếu hệ thống đang bật email verification.
- Có ít nhất 1 conversation để test chat/message/location.
- Có sẵn vài plan/group để test detail/list.

Bạn cần OAuth client id/secret đang dùng cho Flutter app. Set biến môi trường:

```powershell
$env:PLANPAL_USERNAME="testuser"
$env:PLANPAL_PASSWORD="password123"
$env:PLANPAL_CLIENT_ID="your_oauth_client_id"
$env:PLANPAL_CLIENT_SECRET="your_oauth_client_secret"
```

Nếu muốn đo upload ảnh Cloudinary, thêm ảnh test:

```powershell
$env:PLANPAL_TEST_IMAGE_PATH="D:\Study\DoAnNganh\PlanPal\performance_tests\sample.jpg"
```

Nếu không set `PLANPAL_TEST_IMAGE_PATH`, task upload ảnh sẽ tự bỏ qua.

## 4. Chạy Locust UI để chụp màn hình

Chạy:

```powershell
cd D:\Study\DoAnNganh\PlanPal
.\.venv\Scripts\python.exe -m locust -f .\performance_tests\locustfile.py --host=http://127.0.0.1:8000
```

Mở trình duyệt:

```text
http://localhost:8089
```

Điền:

```text
Number of users: 20
Ramp up: 5
Host: http://127.0.0.1:8000
```

Bấm `Start swarming`.

## 5. Các kịch bản nên chạy để đưa vào báo cáo

### Kịch bản 1: Baseline local

Dùng để lấy số đẹp, ổn định cho bảng báo cáo.

```text
Users: 10
Ramp up: 2
Duration: 2-3 phút
```

Chụp:

- Tab `Statistics`.
- Tab `Charts`.

### Kịch bản 2: Normal load

Dùng để chứng minh API vẫn đạt dưới ngưỡng khi có nhiều user hơn.

```text
Users: 50
Ramp up: 5
Duration: 3-5 phút
```

Chụp:

- Statistics có `Average`, `Median`, `95%`.
- Failures bằng `0` hoặc rất thấp.

### Kịch bản 3: Stress nhẹ

Dùng để biết ngưỡng hệ thống bắt đầu chậm.

```text
Users: 100
Ramp up: 10
Duration: 3-5 phút
```

Không bắt buộc đưa vào bảng chính nếu máy local yếu. Có thể đưa vào phần nhận xét.

## 6. Cách đọc số liệu để điền báo cáo

Trong tab `Statistics`, lấy các dòng endpoint chính:

| Báo cáo | Locust endpoint |
|---|---|
| Thời gian phản hồi API GET | `GET /api/v1/plans/`, `GET /api/v1/groups/`, `GET /api/v1/conversations/` |
| Thời gian xử lý dữ liệu phức tạp | `POST /api/v1/plans/` |
| Độ trễ tin nhắn WebSocket/chat | dùng gần đúng `POST /api/v1/conversations/{id}/send_message/ text` |
| Upload ảnh Cloudinary | `POST /api/v1/conversations/{id}/send_message/ image` |
| Notification unread count | `GET /api/v1/notifications/unread-count/` |

Nên ghi `Average` và `95%` thay vì chỉ ghi `Average`.

Ví dụ diễn giải:

```text
GET /api/v1/plans/
Average: 180 ms
P95: 310 ms
Failure: 0%
Đánh giá: Tốt vì P95 < 500 ms.
```

## 7. Chạy headless để xuất file CSV

Nếu muốn có file số liệu kèm báo cáo:

```powershell
cd D:\Study\DoAnNganh\PlanPal
.\.venv\Scripts\python.exe -m locust `
  -f .\performance_tests\locustfile.py `
  --host=http://127.0.0.1:8000 `
  --headless `
  -u 50 `
  -r 5 `
  -t 3m `
  --csv .\performance_tests\results\planpal_50_users
```

Kết quả CSV nằm trong:

```text
performance_tests/results/
```

Các file quan trọng:

- `planpal_50_users_stats.csv`
- `planpal_50_users_failures.csv`
- `planpal_50_users_stats_history.csv`

## 8. Điều kiện cần ghi dưới bảng trong báo cáo

Nên ghi rõ môi trường test:

```text
Môi trường đo:
- Backend: Django local server
- Database: MySQL local
- Redis: Docker local
- Celery: 1 worker solo pool
- Test tool: Locust
- Load: 50 users, ramp-up 5 users/s, duration 3 phút
- Device/network: localhost
```

## 9. Lưu ý quan trọng

- Không dùng tài khoản thật có dữ liệu quan trọng, vì test có tạo plan và gửi message.
- Nếu test upload ảnh, Cloudinary có thể bị tính quota.
- Nếu `Failures` tăng, mở tab `Failures` để xem endpoint nào lỗi.
- Nếu máy local yếu, response time có thể cao do CPU/RAM chứ không hẳn do code.

## 10. Fix 401 Unauthorized khi chạy Locust

Nếu tất cả endpoint trả về `401`, nguyên nhân thường là Locust không lấy được OAuth access token. File `locustfile.py` đã được chỉnh để:

- Hỗ trợ OAuth public client, không bắt buộc `PLANPAL_CLIENT_SECRET`.
- Gửi `/o/token/` bằng JSON body, đúng với backend đang dùng `JSONOAuthLibCore`.
- Hỗ trợ chạy bằng token có sẵn qua `PLANPAL_ACCESS_TOKEN`.
- Dừng Locust user ngay khi login sai, tránh spam request không có token.
- Bỏ qua analytics mặc định vì `/api/v1/analytics/*` là staff-only. Muốn đo analytics thì dùng staff token và set `PLANPAL_INCLUDE_ADMIN_ANALYTICS=true`.

OAuth app hiện tại trong database đang là public password-grant client. Tạo/cập nhật tài khoản test local trước:

```powershell
cd D:\Study\DoAnNganh\PlanPal
.\.venv\Scripts\python.exe .\performance_tests\ensure_perf_user.py
```

Sau đó set biến môi trường:

```powershell
$env:PLANPAL_USERNAME="perf_test_user"
$env:PLANPAL_PASSWORD="password123"
$env:PLANPAL_CLIENT_ID="UhBBWfbCi72eNYMTTn3XqUBR5wGdCcO7TCWmMA7L"
Remove-Item Env:\PLANPAL_CLIENT_SECRET -ErrorAction SilentlyContinue
Remove-Item Env:\PLANPAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
```

Nếu muốn kiểm tra token trước khi chạy Locust:

```powershell
.\.venv\Scripts\python.exe .\performance_tests\auth_smoke_test.py
```

Nếu lệnh này in ra `$env:PLANPAL_ACCESS_TOKEN='...'`, có thể copy dòng đó chạy trong cùng terminal trước khi mở Locust. Nếu không set `PLANPAL_ACCESS_TOKEN`, Locust sẽ tự login bằng username/password/client_id.

Sau đó chạy Locust:

```powershell
cd D:\Study\DoAnNganh\PlanPal
.\.venv\Scripts\python.exe -m locust -f .\performance_tests\locustfile.py --host=http://127.0.0.1:8000
```

Nếu bước lấy token trả về `403 email_not_verified`, tài khoản test chưa xác thực email. Hãy dùng tài khoản đã verify, hoặc verify user test trong admin/database trước khi đo hiệu năng.

Nếu chỉ riêng `GET /api/v1/analytics/summary/` trả về `403`, đó là đúng permission hiện tại: analytics dashboard dành cho staff/admin. Không nên mở quyền endpoint này chỉ để benchmark. Nếu cần đo analytics:

```powershell
.\.venv\Scripts\python.exe .\performance_tests\ensure_perf_user.py --staff

$env:PLANPAL_USERNAME="perf_test_user"
$env:PLANPAL_PASSWORD="password123"
$env:PLANPAL_CLIENT_ID="UhBBWfbCi72eNYMTTn3XqUBR5wGdCcO7TCWmMA7L"
$env:PLANPAL_INCLUDE_ADMIN_ANALYTICS="true"
Remove-Item Env:\PLANPAL_ACCESS_TOKEN -ErrorAction SilentlyContinue
```
