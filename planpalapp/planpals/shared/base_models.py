from uuid import uuid4
from typing import Any

from django.db import models


class BaseModel(models.Model):
    
    id = models.UUIDField(
        primary_key=True,
        default=uuid4,
        editable=False,
        help_text="Unique identifier"
    )
    
    created_at = models.DateTimeField(
        auto_now_add=True,
        db_index=True,
        help_text="Creation time"
    )
    
    updated_at = models.DateTimeField(
        auto_now=True,
        help_text="Last updated time"
    )  # No db_index — rarely filtered, saves write overhead on every table
    
    is_active = models.BooleanField(
        default=True,
        db_index=True,
        help_text="Active status"
    )

    class Meta:
        abstract = True  # Không tạo table riêng
        ordering = ['-created_at']
        
        indexes = [
            models.Index(fields=['created_at']),
            # Removed [updated_at] index — never used in WHERE, wasted write I/O
        ]

    def save(self, *args: Any, **kwargs: Any) -> None:
        self.full_clean()  # Chạy tất cả validations
        super().save(*args, **kwargs)

    def __str__(self) -> str:
        return f"{self.__class__.__name__}({self.id})"
