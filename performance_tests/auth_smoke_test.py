"""
Verify that performance-test credentials can obtain an OAuth token.

Run from the repository root while the Django server is running:
    .\.venv\Scripts\python.exe .\performance_tests\auth_smoke_test.py
"""

from __future__ import annotations

import os
import sys

import requests


HOST = os.getenv("PLANPAL_BASE_URL", "http://127.0.0.1:8000").rstrip("/")
USERNAME = os.getenv("PLANPAL_USERNAME", "perf_test_user")
PASSWORD = os.getenv("PLANPAL_PASSWORD", "password123")
CLIENT_ID = os.getenv("PLANPAL_CLIENT_ID", "UhBBWfbCi72eNYMTTn3XqUBR5wGdCcO7TCWmMA7L")
CLIENT_SECRET = os.getenv("PLANPAL_CLIENT_SECRET", "").strip()
INCLUDE_ADMIN_ANALYTICS = os.getenv("PLANPAL_INCLUDE_ADMIN_ANALYTICS", "").strip().lower() in {
    "1",
    "true",
    "yes",
}


def main() -> int:
    payload = {
        "grant_type": "password",
        "username": USERNAME,
        "password": PASSWORD,
        "client_id": CLIENT_ID,
    }
    if CLIENT_SECRET:
        payload["client_secret"] = CLIENT_SECRET

    try:
        token_response = requests.post(f"{HOST}/o/token/", json=payload, timeout=15)
    except requests.RequestException as exc:
        print(f"AUTH_SMOKE_FAILED token request error: {exc}")
        return 1

    if token_response.status_code != 200:
        print(f"AUTH_SMOKE_FAILED token status={token_response.status_code}")
        print(token_response.text[:500])
        return 1

    token = token_response.json().get("access_token")
    if not token:
        print("AUTH_SMOKE_FAILED response did not include access_token")
        print(token_response.text[:500])
        return 1

    try:
        auth_check_response = requests.get(
            f"{HOST}/api/v1/plans/?limit=1",
            headers={"Authorization": f"Bearer {token}"},
            timeout=15,
        )
    except requests.RequestException as exc:
        print(f"AUTH_SMOKE_FAILED auth-check request error: {exc}")
        return 1

    if auth_check_response.status_code != 200:
        print(f"AUTH_SMOKE_FAILED auth-check status={auth_check_response.status_code}")
        print(auth_check_response.text[:500])
        return 1

    if INCLUDE_ADMIN_ANALYTICS:
        analytics_response = requests.get(
            f"{HOST}/api/v1/analytics/summary/",
            headers={"Authorization": f"Bearer {token}"},
            timeout=15,
        )
        if analytics_response.status_code != 200:
            print(f"AUTH_SMOKE_FAILED analytics status={analytics_response.status_code}")
            print(analytics_response.text[:500])
            print(
                "Analytics requires a staff user. Run: "
                ".\\.venv\\Scripts\\python.exe .\\performance_tests\\ensure_perf_user.py --staff"
            )
            return 1

    print(f"AUTH_SMOKE_OK username={USERNAME}")
    print("Use this session env for Locust if needed:")
    print(f"$env:PLANPAL_ACCESS_TOKEN='{token}'")
    return 0


if __name__ == "__main__":
    sys.exit(main())
