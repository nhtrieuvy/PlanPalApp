"""
Central domain event registry.

Bounded contexts register handlers for domain events they care about.
The ChannelsDomainEventPublisher dispatches events through this registry.

This avoids direct coupling between bounded contexts while allowing
infrastructure to react to domain events.
"""
import logging
from typing import Callable, Dict, List, Type

from planpals.shared.interfaces import DomainEvent

logger = logging.getLogger(__name__)

# Registry: event_type -> list of handler functions
_handlers: Dict[Type[DomainEvent], List[Callable[[DomainEvent], None]]] = {}


def register_event_handler(
    event_type: Type[DomainEvent],
    handler: Callable[[DomainEvent], None],
) -> None:
    """Register a handler for a domain event type."""
    _handlers.setdefault(event_type, []).append(handler)


def dispatch_event(event: DomainEvent) -> None:
    """Dispatch a domain event to all registered handlers."""
    event_type = type(event)
    handlers = _handlers.get(event_type, [])
    for handler in handlers:
        try:
            handler(event)
        except Exception as e:
            logger.error(f"Error handling {event_type.__name__}: {e}", exc_info=True)
