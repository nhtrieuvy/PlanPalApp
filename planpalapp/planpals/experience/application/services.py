from datetime import timedelta
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP

from django.db import transaction
from django.utils import timezone
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError

from planpals.audit.domain.entities import AuditAction, AuditResourceType


class ExperienceService:
    MIN_SHARE_MINUTES = 5
    MAX_SHARE_MINUTES = 480
    SEARCH_TYPES = {'plans', 'groups', 'chats'}

    def __init__(self, repository, realtime=None, audit_service=None):
        self.repository = repository
        self.realtime = realtime
        self.audit_service = audit_service

    def list_group_polls(self, group_id, user_id):
        self._require_group_member(group_id, user_id)
        return self.repository.list_group_polls(group_id, user_id)

    @transaction.atomic
    def create_group_poll(self, group_id, user_id, data, client_mutation_id=None):
        self._require_group_member(group_id, user_id)
        question = str(data.get('question', '')).strip()
        if not question:
            raise ValidationError({'question': 'Question is required.'})
        options = [str(value).strip() for value in data.get('options', [])]
        options = [value for value in options if value]
        if not 2 <= len(options) <= 10:
            raise ValidationError({'options': 'A poll requires 2 to 10 options.'})
        if len({value.casefold() for value in options}) != len(options):
            raise ValidationError({'options': 'Poll options must be unique.'})
        closes_at = data.get('closes_at')
        if closes_at and closes_at <= timezone.now():
            raise ValidationError({'closes_at': 'Closing time must be in the future.'})
        poll = self.repository.create_group_poll(
            group_id,
            user_id,
            {
                'question': question,
                'options': options,
                'allow_multiple': bool(data.get('allow_multiple', False)),
                'closes_at': closes_at,
                'client_mutation_id': (client_mutation_id or '').strip() or None,
            },
        )
        if getattr(poll, '_was_created', True):
            self._publish_group(group_id, 'group.poll_created', {'poll_id': str(poll.id)})
            self._audit(
                user_id,
                AuditAction.CREATE_GROUP_POLL.value,
                AuditResourceType.GROUP.value,
                group_id,
                {'poll_id': str(poll.id), 'question': poll.question},
            )
        return poll

    @transaction.atomic
    def vote_group_poll(self, poll_id, user_id, option_ids):
        poll = self.repository.get_group_poll(poll_id, for_update=True)
        if poll is None:
            raise NotFound('Poll was not found.')
        self._require_group_member(poll.group_id, user_id)
        if poll.is_closed or (poll.closes_at and poll.closes_at <= timezone.now()):
            raise ValidationError({'poll': 'This poll is closed.'})
        normalized = list(dict.fromkeys(option_ids or []))
        if not normalized:
            raise ValidationError({'option_ids': 'Select at least one option.'})
        if not poll.allow_multiple and len(normalized) != 1:
            raise ValidationError({'option_ids': 'Only one option can be selected.'})
        valid_ids = {option.id for option in poll.options.all()}
        if any(option_id not in valid_ids for option_id in normalized):
            raise ValidationError({'option_ids': 'An option does not belong to this poll.'})
        updated = self.repository.replace_poll_votes(poll, user_id, normalized)
        self._publish_group(
            poll.group_id,
            'group.poll_voted',
            {'poll_id': str(poll.id), 'user_id': str(user_id)},
        )
        return updated

    @transaction.atomic
    def close_group_poll(self, poll_id, user_id):
        poll = self.repository.get_group_poll(poll_id, for_update=True)
        if poll is None:
            raise NotFound('Poll was not found.')
        if poll.created_by_id != user_id and not self.repository.can_manage_group(
            poll.group_id, user_id
        ):
            raise PermissionDenied('Only the poll creator or a group manager can close it.')
        updated = self.repository.close_poll(poll.id)
        self._publish_group(poll.group_id, 'group.poll_closed', {'poll_id': str(poll.id)})
        self._audit(
            user_id,
            AuditAction.CLOSE_GROUP_POLL.value,
            AuditResourceType.GROUP.value,
            poll.group_id,
            {'poll_id': str(poll.id), 'question': poll.question},
        )
        return updated

    def list_live_locations(self, conversation_id, user_id):
        self._require_conversation_access(conversation_id, user_id)
        return self.repository.list_live_locations(conversation_id)

    @transaction.atomic
    def start_live_location(
        self, conversation_id, user_id, data, client_mutation_id=None
    ):
        self._require_conversation_access(conversation_id, user_id)
        if data.get('consent') is not True:
            raise ValidationError({'consent': 'Explicit location-sharing consent is required.'})
        duration = int(data.get('duration_minutes', 60))
        if not self.MIN_SHARE_MINUTES <= duration <= self.MAX_SHARE_MINUTES:
            raise ValidationError({
                'duration_minutes': (
                    f'Duration must be between {self.MIN_SHARE_MINUTES} and '
                    f'{self.MAX_SHARE_MINUTES} minutes.'
                )
            })
        coordinates = self._coordinates(data)
        share = self.repository.create_live_location(
            conversation_id,
            user_id,
            {
                **coordinates,
                'expires_at': timezone.now() + timedelta(minutes=duration),
                'client_mutation_id': (client_mutation_id or '').strip() or None,
            },
        )
        if getattr(share, '_was_created', True):
            self._publish_location(share, 'live_location.started')
            self._audit(
                user_id,
                AuditAction.START_LIVE_LOCATION.value,
                AuditResourceType.CONVERSATION.value,
                conversation_id,
                {'share_id': str(share.id), 'expires_at': share.expires_at},
            )
        return share

    @transaction.atomic
    def update_live_location(self, share_id, user_id, data):
        share = self.repository.get_live_location(share_id, for_update=True)
        if share is None:
            raise NotFound('Live location share was not found.')
        if share.user_id != user_id:
            raise PermissionDenied('Only the sharing user can update this location.')
        if not share.is_active or share.expires_at <= timezone.now():
            raise ValidationError({'share': 'This live location share has ended.'})
        updated = self.repository.update_live_location(share.id, self._coordinates(data))
        self._publish_location(updated, 'live_location.updated')
        return updated

    @transaction.atomic
    def stop_live_location(self, share_id, user_id):
        share = self.repository.get_live_location(share_id, for_update=True)
        if share is None:
            raise NotFound('Live location share was not found.')
        if share.user_id != user_id:
            raise PermissionDenied('Only the sharing user can stop this location.')
        updated = self.repository.update_live_location(
            share.id,
            {'is_active': False, 'stopped_at': timezone.now()},
        )
        self._publish_location(updated, 'live_location.stopped')
        self._audit(
            user_id,
            AuditAction.STOP_LIVE_LOCATION.value,
            AuditResourceType.CONVERSATION.value,
            share.conversation_id,
            {'share_id': str(share.id)},
        )
        return updated

    def _audit(self, user_id, action, resource_type, resource_id, metadata):
        if self.audit_service is None:
            return
        self.audit_service.log_action(
            user=user_id,
            action=action,
            resource_type=resource_type,
            resource_id=resource_id,
            metadata=metadata,
        )

    def global_search(self, user_id, query, types=None, limit=8):
        normalized = str(query or '').strip()
        if len(normalized) < 2:
            raise ValidationError({'q': 'Enter at least 2 characters.'})
        requested_types = set(types or self.SEARCH_TYPES) & self.SEARCH_TYPES
        if not requested_types:
            requested_types = set(self.SEARCH_TYPES)
        safe_limit = max(1, min(int(limit or 8), 20))
        return self.repository.global_search(
            user_id, normalized, requested_types, safe_limit
        )

    def _require_group_member(self, group_id, user_id):
        if not self.repository.is_group_member(group_id, user_id):
            raise PermissionDenied('Only group members can use polls.')

    def _require_conversation_access(self, conversation_id, user_id):
        if not self.repository.can_access_conversation(conversation_id, user_id):
            raise PermissionDenied('You do not have access to this conversation.')

    @staticmethod
    def _coordinates(data):
        try:
            latitude = Decimal(str(data.get('latitude'))).quantize(
                Decimal('0.000001'), rounding=ROUND_HALF_UP
            )
            longitude = Decimal(str(data.get('longitude'))).quantize(
                Decimal('0.000001'), rounding=ROUND_HALF_UP
            )
            accuracy = data.get('accuracy_meters')
            accuracy = (
                Decimal(str(accuracy)).quantize(
                    Decimal('0.01'), rounding=ROUND_HALF_UP
                )
                if accuracy is not None
                else None
            )
        except (InvalidOperation, TypeError, ValueError) as exc:
            raise ValidationError({'coordinates': 'Valid coordinates are required.'}) from exc
        if not Decimal('-90') <= latitude <= Decimal('90'):
            raise ValidationError({'latitude': 'Latitude must be between -90 and 90.'})
        if not Decimal('-180') <= longitude <= Decimal('180'):
            raise ValidationError({'longitude': 'Longitude must be between -180 and 180.'})
        if accuracy is not None and accuracy < 0:
            raise ValidationError({'accuracy_meters': 'Accuracy cannot be negative.'})
        return {
            'latitude': latitude,
            'longitude': longitude,
            'accuracy_meters': accuracy,
        }

    def _publish_group(self, group_id, event, data):
        if self.realtime:
            self.realtime.publish_group(group_id, event, data)

    def _publish_location(self, share, event):
        if self.realtime:
            self.realtime.publish_conversation(
                share.conversation_id,
                event,
                {
                    'share_id': str(share.id),
                    'conversation_id': str(share.conversation_id),
                    'user_id': str(share.user_id),
                    'latitude': float(share.latitude),
                    'longitude': float(share.longitude),
                    'accuracy_meters': (
                        float(share.accuracy_meters)
                        if share.accuracy_meters is not None else None
                    ),
                    'expires_at': share.expires_at.isoformat(),
                    'is_active': share.is_active,
                },
            )
