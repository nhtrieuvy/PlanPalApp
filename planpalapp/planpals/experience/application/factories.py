from planpals.experience.application.services import ExperienceService
from planpals.experience.infrastructure.realtime import ExperienceRealtimePublisher
from planpals.experience.infrastructure.repositories import DjangoExperienceRepository


def get_experience_service():
    from planpals.audit.application.factories import get_audit_log_service

    return ExperienceService(
        repository=DjangoExperienceRepository(),
        realtime=ExperienceRealtimePublisher(),
        audit_service=get_audit_log_service(),
    )
