from planpals.audit.application.factories import get_audit_log_service
from planpals.collaboration.application.services import CollaborationService
from planpals.collaboration.infrastructure.realtime import CollaborationRealtimePublisher
from planpals.collaboration.infrastructure.repositories import DjangoCollaborationRepository


def get_collaboration_service() -> CollaborationService:
    return CollaborationService(
        repository=DjangoCollaborationRepository(),
        audit_service=get_audit_log_service(),
        realtime_publisher=CollaborationRealtimePublisher(),
    )
