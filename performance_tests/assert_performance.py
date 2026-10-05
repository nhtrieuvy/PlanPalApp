"""Fail a repeatable Locust run when agreed service-level thresholds regress."""

from __future__ import annotations

import csv
import os
import sys
from pathlib import Path


def _float_env(name: str, default: float) -> float:
    try:
        return float(os.getenv(name, str(default)))
    except ValueError:
        return default


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: python assert_performance.py <locust_stats.csv>")
        return 2

    stats_path = Path(sys.argv[1])
    with stats_path.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    aggregated = next((row for row in rows if row.get("Name") == "Aggregated"), None)
    if aggregated is None:
        print(f"No Aggregated row found in {stats_path}")
        return 2

    requests = int(aggregated.get("Request Count") or 0)
    failures = int(aggregated.get("Failure Count") or 0)
    average_ms = float(aggregated.get("Average Response Time") or 0)
    p95_ms = float(aggregated.get("95%") or 0)
    failure_pct = (failures / requests * 100) if requests else 100.0

    max_average = _float_env("PLANPAL_MAX_AVG_MS", 500)
    max_p95 = _float_env("PLANPAL_MAX_P95_MS", 1500)
    max_failure_pct = _float_env("PLANPAL_MAX_FAILURE_PERCENT", 1)
    violations = []
    if average_ms > max_average:
        violations.append(f"average {average_ms:.2f}ms > {max_average:.2f}ms")
    if p95_ms > max_p95:
        violations.append(f"p95 {p95_ms:.2f}ms > {max_p95:.2f}ms")
    if failure_pct > max_failure_pct:
        violations.append(
            f"failures {failure_pct:.2f}% > {max_failure_pct:.2f}%"
        )

    print(
        f"requests={requests} failures={failures} average_ms={average_ms:.2f} "
        f"p95_ms={p95_ms:.2f} failure_percent={failure_pct:.2f}"
    )
    if violations:
        print("PERFORMANCE_CHECK_FAILED: " + "; ".join(violations))
        return 1
    print("PERFORMANCE_CHECK_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
