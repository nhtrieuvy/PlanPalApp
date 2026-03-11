"""
API-layer exception aliases — backward-compatible re-exports.

The canonical domain exceptions live in shared/domain_exceptions.py (pure Python).
This file re-exports them so that existing ``from planpals.shared.exceptions import …``
statements in API/presentation code continue to work.

Application-layer handlers should import from ``shared.domain_exceptions`` instead.
"""
# Re-export everything from the pure-Python domain exceptions module.
from planpals.shared.domain_exceptions import *  # noqa: F401,F403
from planpals.shared.domain_exceptions import DomainException  # noqa: F401

# Backward-compat alias used by exception_handler.py
PlanPalException = DomainException
