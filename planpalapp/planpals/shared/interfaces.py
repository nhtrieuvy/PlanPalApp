"""
Shared interfaces and base abstractions for Clean Architecture.

These are the building blocks that all bounded contexts use:
- BaseRepository: Abstract interface for data access
- BaseCommand: Immutable data transfer objects for mutations
- BaseCommandHandler: Processes commands using repositories
- BaseQueryService: Read-only data access for views
"""
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import TypeVar, Generic, Optional, List, Any, Dict
from uuid import UUID
import logging

logger = logging.getLogger(__name__)

# ============================================================================
# REPOSITORY PATTERN
# ============================================================================

T = TypeVar('T')


class BaseRepository(ABC, Generic[T]):
    """
    Abstract repository interface. Domain/Application layers depend on this.
    Infrastructure layer provides Django ORM implementations.
    
    The Dependency Rule: Domain -> Application -> Infrastructure
    But dependencies point INWARD: Infrastructure implements Domain interfaces.
    """

    @abstractmethod
    def get_by_id(self, entity_id: UUID) -> Optional[T]:
        """Retrieve a single entity by its ID."""
        ...

    @abstractmethod
    def save(self, entity: T) -> T:
        """Persist an entity (create or update)."""
        ...

    @abstractmethod
    def delete(self, entity_id: UUID) -> bool:
        """Delete an entity by ID. Returns True if deleted."""
        ...

    @abstractmethod
    def exists(self, entity_id: UUID) -> bool:
        """Check if an entity exists."""
        ...


# ============================================================================
# COMMAND + HANDLER PATTERN (for mutations)
# ============================================================================

@dataclass(frozen=True)
class BaseCommand:
    """
    Immutable value object representing a mutation request.
    Commands carry ALL the data needed to perform an operation.
    
    Rules:
    - Commands are pure data — no business logic
    - Commands are immutable (frozen=True)
    - Commands do NOT depend on Django/DRF
    """
    pass


CommandT = TypeVar('CommandT', bound=BaseCommand)
ResultT = TypeVar('ResultT')


class BaseCommandHandler(ABC, Generic[CommandT, ResultT]):
    """
    Processes a Command and returns a Result.

    Handlers contain the USE CASE logic:
    - Validate business rules
    - Coordinate repositories
    - Publish domain events
    
    Handlers depend on repository INTERFACES, not on Django ORM directly.
    """

    @abstractmethod
    def handle(self, command: CommandT) -> ResultT:
        """Execute the command and return the result."""
        ...

    def _log(self, message: str, **kwargs):
        logger.info(f"[{self.__class__.__name__}] {message}", extra=kwargs)

    def _log_error(self, message: str, error: Exception = None, **kwargs):
        logger.error(
            f"[{self.__class__.__name__}] {message}: {error}" if error else f"[{self.__class__.__name__}] {message}",
            extra=kwargs,
            exc_info=bool(error),
        )


# ============================================================================
# DOMAIN EVENTS (for decoupled side-effects)
# ============================================================================

@dataclass(frozen=True)
class DomainEvent:
    """
    Immutable value object representing something that happened in the domain.
    
    Domain events are raised by handlers and consumed by infrastructure
    (e.g., to publish WebSocket events, send push notifications).
    
    This decouples business logic from infrastructure concerns.
    """
    pass


class DomainEventPublisher(ABC):
    """
    Interface for publishing domain events.
    Infrastructure provides the implementation (e.g., Django signals, Channels).
    """

    @abstractmethod
    def publish(self, event: DomainEvent) -> None:
        """Publish a domain event to interested subscribers."""
        ...


# ============================================================================
# UNIT OF WORK (optional, for transactional consistency)
# ============================================================================

class UnitOfWork(ABC):
    """
    Manages transactional boundaries.
    Ensures all repository operations within a use case succeed or fail together.
    """

    @abstractmethod
    def __enter__(self):
        ...

    @abstractmethod
    def __exit__(self, exc_type, exc_val, exc_tb):
        ...

    @abstractmethod
    def commit(self):
        ...

    @abstractmethod
    def rollback(self):
        ...
