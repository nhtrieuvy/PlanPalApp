"""
Chat Domain — Pure Python Entities, Value Objects & Constants

This file is the innermost layer of Clean Architecture.
NO Django imports, NO ORM, NO REST framework — Pure Python only.

All bounded contexts and external layers may depend on these definitions,
but this file must NEVER import from application, infrastructure, or presentation.
"""
from enum import Enum
from typing import Optional
from decimal import Decimal


# ============================================================================
# Enums / Constants
# ============================================================================

class ConversationType(str, Enum):
    DIRECT = 'direct'
    GROUP = 'group'

    CHOICES = [
        ('direct', 'Chat cá nhân'),
        ('group', 'Chat nhóm'),
    ]


class MessageType(str, Enum):
    TEXT = 'text'
    IMAGE = 'image'
    FILE = 'file'
    LOCATION = 'location'
    SYSTEM = 'system'

    CHOICES = [
        ('text', 'Văn bản'),
        ('image', 'Hình ảnh'),
        ('file', 'File đính kèm'),
        ('location', 'Vị trí'),
        ('system', 'Thông báo hệ thống'),
    ]


# ============================================================================
# Pure validation functions
# ============================================================================

def validate_coordinates(latitude: Optional[Decimal], longitude: Optional[Decimal]) -> Optional[str]:
    """Returns error message or None if valid."""
    if latitude is not None and not (-90 <= latitude <= 90):
        return "Latitude must be between -90 and 90"
    if longitude is not None and not (-180 <= longitude <= 180):
        return "Longitude must be between -180 and 180"
    return None
