"""
Groups Domain — Pure Python Entities, Value Objects & Constants

This file is the innermost layer of Clean Architecture.
NO Django imports, NO ORM, NO REST framework — Pure Python only.

All bounded contexts and external layers may depend on these definitions,
but this file must NEVER import from application, infrastructure, or presentation.
"""
from enum import Enum


# ============================================================================
# Enums / Constants
# ============================================================================

class MembershipRole(str, Enum):
    ADMIN = 'admin'
    MEMBER = 'member'

    CHOICES = [
        ('admin', 'Quản trị viên'),
        ('member', 'Thành viên'),
    ]
