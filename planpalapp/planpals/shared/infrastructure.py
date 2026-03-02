"""
Django-specific infrastructure implementations of shared interfaces.

These live in shared/infrastructure because they are used by ALL bounded contexts.
"""
from django.db import transaction

from planpals.shared.interfaces import UnitOfWork, DomainEvent, DomainEventPublisher


class DjangoUnitOfWork(UnitOfWork):
    """
    Django transaction-based Unit of Work.
    Wraps all repository operations in a single database transaction.
    
    Usage:
        with DjangoUnitOfWork() as uow:
            repo.save(entity)
            uow.commit()
    """

    def __init__(self):
        self._atomic = None

    def __enter__(self):
        self._atomic = transaction.atomic()
        self._atomic.__enter__()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self._atomic:
            return self._atomic.__exit__(exc_type, exc_val, exc_tb)

    def commit(self):
        """Commit is implicit in Django's atomic() — exiting without error commits."""
        pass

    def rollback(self):
        """Force rollback by raising an exception inside atomic block."""
        transaction.set_rollback(True)


class ChannelsDomainEventPublisher(DomainEventPublisher):
    """
    Publishes domain events via Django Channels + FCM push notifications.
    
    This is the bridge between domain events (pure data) and infrastructure
    (WebSocket broadcasting, push notifications).
    
    Handlers call: publisher.publish(PlanCreatedEvent(...))
    This class maps the event to the appropriate realtime/push channels.
    """

    def publish(self, event: DomainEvent) -> None:
        # Domain events are dispatched to specific publishers
        # based on the event type. Import lazily to avoid circular dependencies.
        from django.db import transaction as db_transaction

        # Defer publishing until after the transaction commits
        # to avoid sending events for rolled-back data.
        db_transaction.on_commit(lambda: self._dispatch(event))

    def _dispatch(self, event: DomainEvent) -> None:
        """
        Route domain events to infrastructure publishers.
        Each bounded context registers its own event handlers.
        """
        from planpals.shared._event_registry import dispatch_event
        dispatch_event(event)
