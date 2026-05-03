import os
import random
from datetime import datetime, timedelta, timezone
from pathlib import Path

from locust import HttpUser, between, events, task
from locust.exception import StopUser


def _env(name: str, default: str = "") -> str:
    return os.getenv(name, default).strip()


class PlanPalApiUser(HttpUser):
    """
    Locust user that simulates common PlanPal mobile flows.

    Required env vars:
      PLANPAL_ACCESS_TOKEN

    Or, if PLANPAL_ACCESS_TOKEN is not provided:
      PLANPAL_USERNAME
      PLANPAL_PASSWORD
      PLANPAL_CLIENT_ID

    Optional env vars:
      PLANPAL_CLIENT_SECRET
      PLANPAL_INCLUDE_ADMIN_ANALYTICS
      PLANPAL_TEST_IMAGE_PATH
    """

    wait_time = between(0.8, 2.5)

    token: str | None = None
    plan_ids: list[str]
    group_ids: list[str]
    conversation_ids: list[str]
    include_admin_analytics: bool

    def on_start(self) -> None:
        self.plan_ids = []
        self.group_ids = []
        self.conversation_ids = []
        self.include_admin_analytics = _env("PLANPAL_INCLUDE_ADMIN_ANALYTICS").lower() in {
            "1",
            "true",
            "yes",
        }
        self._authenticate()
        self._assert_authenticated()
        if self.include_admin_analytics:
            self._assert_analytics_authorized()
        self._warmup_ids()

    @property
    def auth_headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.token}"} if self.token else {}

    def _authenticate(self) -> None:
        access_token = _env("PLANPAL_ACCESS_TOKEN")
        if access_token:
            self.token = access_token
            return

        self._login()

    def _login(self) -> None:
        username = _env("PLANPAL_USERNAME")
        password = _env("PLANPAL_PASSWORD")
        client_id = _env("PLANPAL_CLIENT_ID")
        client_secret = _env("PLANPAL_CLIENT_SECRET")

        missing = [
            name
            for name, value in {
                "PLANPAL_USERNAME": username,
                "PLANPAL_PASSWORD": password,
                "PLANPAL_CLIENT_ID": client_id,
            }.items()
            if not value
        ]
        if missing:
            raise StopUser(
                "Missing authentication env vars: "
                + ", ".join(missing)
                + ". Set PLANPAL_ACCESS_TOKEN or username/password/client_id."
            )

        login_payload = {
            "grant_type": "password",
            "username": username,
            "password": password,
            "client_id": client_id,
        }
        if client_secret:
            login_payload["client_secret"] = client_secret

        with self.client.post(
            "/o/token/",
            json=login_payload,
            name="AUTH /o/token/",
            catch_response=True,
        ) as response:
            if response.status_code != 200:
                response.failure(f"Login failed: {response.status_code} {response.text[:200]}")
                raise StopUser(
                    "OAuth login failed. Check PLANPAL_USERNAME, PLANPAL_PASSWORD, "
                    "PLANPAL_CLIENT_ID and optional PLANPAL_CLIENT_SECRET."
                )

            try:
                self.token = response.json()["access_token"]
                response.success()
            except Exception as exc:
                response.failure(f"Invalid login response: {exc}")
                raise StopUser("OAuth login response did not contain access_token.")

    def _assert_authenticated(self) -> None:
        if not self.token:
            raise StopUser("Authentication failed before API warmup.")

        with self.client.get(
            "/api/v1/plans/?limit=1",
            headers=self.auth_headers,
            name="AUTH CHECK /api/v1/plans/",
            catch_response=True,
        ) as response:
            if response.status_code == 200:
                response.success()
                return

            response.failure(f"Authenticated check failed: {response.status_code} {response.text[:200]}")
            raise StopUser(
                "Access token was rejected by the API. Refresh PLANPAL_ACCESS_TOKEN "
                "or verify OAuth credentials."
            )

    def _assert_analytics_authorized(self) -> None:
        with self.client.get(
            "/api/v1/analytics/summary/",
            headers=self.auth_headers,
            name="AUTH CHECK /api/v1/analytics/summary/",
            catch_response=True,
        ) as response:
            if response.status_code == 200:
                response.success()
                return

            response.failure(f"Analytics auth-check failed: {response.status_code} {response.text[:200]}")
            raise StopUser(
                "PLANPAL_INCLUDE_ADMIN_ANALYTICS=true requires a staff/admin user. "
                "Run: .\\.venv\\Scripts\\python.exe .\\performance_tests\\ensure_perf_user.py --staff, "
                "then remove stale PLANPAL_ACCESS_TOKEN and restart Locust."
            )

    def _warmup_ids(self) -> None:
        if not self.token:
            return

        plans_response = self.client.get(
            "/api/v1/plans/?limit=20",
            headers=self.auth_headers,
            name="WARMUP GET /api/v1/plans/",
        )
        if plans_response.ok:
            self.plan_ids = self._extract_ids(plans_response.json(), "results")

        groups_response = self.client.get(
            "/api/v1/groups/",
            headers=self.auth_headers,
            name="WARMUP GET /api/v1/groups/",
        )
        if groups_response.ok:
            self.group_ids = self._extract_ids(groups_response.json(), "results")

        conversations_response = self.client.get(
            "/api/v1/conversations/",
            headers=self.auth_headers,
            name="WARMUP GET /api/v1/conversations/",
        )
        if conversations_response.ok:
            data = conversations_response.json()
            conversations = data.get("conversations", [])
            self.conversation_ids = [
                str(item["id"])
                for item in conversations
                if isinstance(item, dict) and item.get("id")
            ]

    def _extract_ids(self, data: object, key: str) -> list[str]:
        if isinstance(data, list):
            items = data
        elif isinstance(data, dict):
            items = data.get(key, data.get("plans", data.get("groups", [])))
        else:
            items = []

        return [
            str(item["id"])
            for item in items
            if isinstance(item, dict) and item.get("id")
        ]

    @task(8)
    def get_plans(self) -> None:
        self.client.get(
            "/api/v1/plans/?limit=20",
            headers=self.auth_headers,
            name="GET /api/v1/plans/",
        )

    @task(6)
    def get_groups(self) -> None:
        self.client.get(
            "/api/v1/groups/",
            headers=self.auth_headers,
            name="GET /api/v1/groups/",
        )

    @task(5)
    def get_conversations(self) -> None:
        self.client.get(
            "/api/v1/conversations/",
            headers=self.auth_headers,
            name="GET /api/v1/conversations/",
        )

    @task(5)
    def get_notifications_unread_count(self) -> None:
        self.client.get(
            "/api/v1/notifications/unread-count/",
            headers=self.auth_headers,
            name="GET /api/v1/notifications/unread-count/",
        )

    @task(3)
    def get_plan_detail(self) -> None:
        if not self.plan_ids:
            return

        plan_id = random.choice(self.plan_ids)
        self.client.get(
            f"/api/v1/plans/{plan_id}/",
            headers=self.auth_headers,
            name="GET /api/v1/plans/{id}/",
        )

    @task(2)
    def get_analytics_summary(self) -> None:
        if not self.include_admin_analytics:
            return

        self.client.get(
            "/api/v1/analytics/summary/",
            headers=self.auth_headers,
            name="GET /api/v1/analytics/summary/",
        )

    @task(2)
    def get_messages(self) -> None:
        if not self.conversation_ids:
            return

        conversation_id = random.choice(self.conversation_ids)
        self.client.get(
            f"/api/v1/conversations/{conversation_id}/messages/?limit=30",
            headers=self.auth_headers,
            name="GET /api/v1/conversations/{id}/messages/",
        )

    @task(1)
    def create_personal_plan(self) -> None:
        now = datetime.now(timezone.utc) + timedelta(days=random.randint(5, 30))
        end = now + timedelta(days=random.randint(1, 3))
        payload = {
            "title": f"Perf Plan {random.randint(100000, 999999)}",
            "description": "Created by Locust performance test",
            "plan_type": "personal",
            "is_public": False,
            "start_date": now.isoformat(),
            "end_date": end.isoformat(),
        }

        with self.client.post(
            "/api/v1/plans/",
            json=payload,
            headers=self.auth_headers,
            name="POST /api/v1/plans/",
            catch_response=True,
        ) as response:
            if response.status_code != 201:
                response.failure(f"Create plan failed: {response.status_code} {response.text[:200]}")
                return

            try:
                plan_id = str(response.json()["id"])
                self.plan_ids.append(plan_id)
                response.success()
            except Exception as exc:
                response.failure(f"Invalid create plan response: {exc}")

    @task(1)
    def send_chat_text_message(self) -> None:
        if not self.conversation_ids:
            return

        conversation_id = random.choice(self.conversation_ids)
        self.client.post(
            f"/api/v1/conversations/{conversation_id}/send_message/",
            json={
                "message_type": "text",
                "content": f"Locust ping {random.randint(100000, 999999)}",
            },
            headers=self.auth_headers,
            name="POST /api/v1/conversations/{id}/send_message/ text",
        )

    @task(1)
    def send_chat_location_message(self) -> None:
        if not self.conversation_ids:
            return

        conversation_id = random.choice(self.conversation_ids)
        self.client.post(
            f"/api/v1/conversations/{conversation_id}/send_message/",
            json={
                "message_type": "location",
                "content": "Performance test location",
                "latitude": 10.762622,
                "longitude": 106.660172,
                "location_name": "Ho Chi Minh City",
            },
            headers=self.auth_headers,
            name="POST /api/v1/conversations/{id}/send_message/ location",
        )

    @task(1)
    def upload_chat_image_if_configured(self) -> None:
        image_path = _env("PLANPAL_TEST_IMAGE_PATH")
        if not image_path or not self.conversation_ids:
            return

        path = Path(image_path)
        if not path.exists():
            return

        conversation_id = random.choice(self.conversation_ids)
        with path.open("rb") as image_file:
            self.client.post(
                f"/api/v1/conversations/{conversation_id}/send_message/",
                data={
                    "message_type": "image",
                    "attachment_name": path.name,
                    "attachment_size": str(path.stat().st_size),
                },
                files={"attachment": (path.name, image_file, "image/jpeg")},
                headers=self.auth_headers,
                name="POST /api/v1/conversations/{id}/send_message/ image",
            )


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs) -> None:
    stats = environment.stats.total
    print("\n=== PlanPal Performance Summary ===")
    print(f"Requests: {stats.num_requests}")
    print(f"Failures: {stats.num_failures}")
    print(f"Average response time: {stats.avg_response_time:.2f} ms")
    print(f"Median response time: {stats.median_response_time:.2f} ms")
    print(f"P95 response time: {stats.get_response_time_percentile(0.95):.2f} ms")
    print(f"P99 response time: {stats.get_response_time_percentile(0.99):.2f} ms")
    print("===================================\n")
