from django.utils import timezone
from rest_framework import serializers


class GroupPollCreateSerializer(serializers.Serializer):
    question = serializers.CharField(max_length=240)
    options = serializers.ListField(
        child=serializers.CharField(max_length=160),
        min_length=2,
        max_length=10,
    )
    allow_multiple = serializers.BooleanField(required=False, default=False)
    closes_at = serializers.DateTimeField(required=False, allow_null=True)


class GroupPollVoteSerializer(serializers.Serializer):
    option_ids = serializers.ListField(
        child=serializers.UUIDField(), min_length=1, max_length=10
    )


class GroupPollSerializer:
    @staticmethod
    def from_model(poll, viewer_id):
        now = timezone.now()
        closed = poll.is_closed or bool(poll.closes_at and poll.closes_at <= now)
        options = []
        selected_ids = []
        total_votes = 0
        for option in poll.options.all():
            votes = list(option.votes.all())
            vote_count = getattr(option, 'vote_count', len(votes))
            total_votes += vote_count
            if any(vote.user_id == viewer_id for vote in votes):
                selected_ids.append(str(option.id))
            options.append({
                'id': str(option.id),
                'text': option.text,
                'vote_count': vote_count,
            })
        return {
            'id': str(poll.id),
            'group_id': str(poll.group_id),
            'question': poll.question,
            'allow_multiple': poll.allow_multiple,
            'closes_at': poll.closes_at,
            'is_closed': closed,
            'created_by': {
                'id': str(poll.created_by_id),
                'username': poll.created_by.username,
                'full_name': poll.created_by.get_full_name(),
            },
            'options': options,
            'selected_option_ids': selected_ids,
            'total_votes': total_votes,
            'created_at': poll.created_at,
        }


class LiveLocationStartSerializer(serializers.Serializer):
    latitude = serializers.DecimalField(max_digits=9, decimal_places=6)
    longitude = serializers.DecimalField(max_digits=9, decimal_places=6)
    accuracy_meters = serializers.DecimalField(
        max_digits=8, decimal_places=2, required=False, allow_null=True, min_value=0
    )
    duration_minutes = serializers.IntegerField(min_value=5, max_value=480)
    consent = serializers.BooleanField()


class LiveLocationUpdateSerializer(serializers.Serializer):
    latitude = serializers.DecimalField(max_digits=9, decimal_places=6)
    longitude = serializers.DecimalField(max_digits=9, decimal_places=6)
    accuracy_meters = serializers.DecimalField(
        max_digits=8, decimal_places=2, required=False, allow_null=True, min_value=0
    )


class LiveLocationSerializer:
    @staticmethod
    def from_model(share):
        return {
            'id': str(share.id),
            'conversation_id': str(share.conversation_id),
            'user': {
                'id': str(share.user_id),
                'username': share.user.username,
                'full_name': share.user.get_full_name(),
                'avatar_url': getattr(share.user, 'avatar_url', None),
            },
            'latitude': share.latitude,
            'longitude': share.longitude,
            'accuracy_meters': share.accuracy_meters,
            'consent_granted_at': share.consent_granted_at,
            'expires_at': share.expires_at,
            'is_active': share.is_active and share.expires_at > timezone.now(),
            'stopped_at': share.stopped_at,
            'updated_at': share.updated_at,
        }


class GlobalSearchQuerySerializer(serializers.Serializer):
    q = serializers.CharField(min_length=2, max_length=100)
    types = serializers.CharField(required=False, allow_blank=True)
    limit = serializers.IntegerField(required=False, min_value=1, max_value=20, default=8)

    def parsed_types(self):
        raw = self.validated_data.get('types', '')
        return [value.strip() for value in raw.split(',') if value.strip()]
