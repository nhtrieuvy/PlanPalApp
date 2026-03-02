"""
DEPRECATED: ORM models have been moved to infrastructure/models.py

This file previously contained Django ORM model definitions.
As part of the Clean Architecture refactoring (Dependency Rule enforcement),
all ORM models now live in the infrastructure layer.

Import models from:
  - planpals.{context}.infrastructure.models  (direct)
  - planpals.models                           (facade)

The domain layer (this directory) now contains only:
  - entities.py   : Pure Python enums, constants, validation functions
  - repositories.py: Abstract repository interfaces (ABCs)
  - events.py     : Pure Python domain event dataclasses
"""

