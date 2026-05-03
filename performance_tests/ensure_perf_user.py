"""
Create or update a local-only user for PlanPal performance tests.

Run from the repository root:
    .\.venv\Scripts\python.exe .\performance_tests\ensure_perf_user.py

This script does not change application code or API behavior. It only ensures
that Locust has a verified, active account in the local development database.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
BACKEND_DIR = PROJECT_ROOT / "planpalapp"

sys.path.insert(0, str(BACKEND_DIR))
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "planpalapp.settings")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create or update a local-only PlanPal performance-test user.",
    )
    parser.add_argument("--username", default=os.getenv("PLANPAL_PERF_USERNAME", "perf_test_user"))
    parser.add_argument("--password", default=os.getenv("PLANPAL_PERF_PASSWORD", "password123"))
    parser.add_argument("--email", default=None)
    parser.add_argument(
        "--staff",
        action="store_true",
        default=os.getenv("PLANPAL_PERF_IS_STAFF", "").strip().lower() in {
            "1",
            "true",
            "yes",
        },
        help="Grant Django staff permission so analytics admin endpoints return 200.",
    )
    parser.add_argument(
        "--non-staff",
        action="store_true",
        help="Explicitly remove Django staff permission.",
    )
    args = parser.parse_args()

    import django

    django.setup()

    from django.contrib.auth import get_user_model
    from django.utils import timezone

    username = args.username
    password = args.password
    email = args.email or os.getenv("PLANPAL_PERF_EMAIL", f"{username}@example.com")
    is_staff = False if args.non_staff else args.staff

    User = get_user_model()
    user = User.objects.filter(username=username).first()
    created = user is None
    if user is None:
        user = User(username=username)

    user.email = email
    user.is_active = True
    user.is_staff = is_staff
    user.email_verified_at = user.email_verified_at or timezone.now()
    user.set_password(password)
    if created:
        user.save()
    else:
        user.save(update_fields=[
            "email",
            "is_active",
            "is_staff",
            "email_verified_at",
            "password",
        ])

    status = "created" if created else "updated"
    print(
        f"Performance user {status}: username={username}, "
        f"password={password}, is_staff={is_staff}"
    )


if __name__ == "__main__":
    main()
