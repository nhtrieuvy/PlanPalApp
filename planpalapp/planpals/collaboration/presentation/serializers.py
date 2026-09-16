from collections import Counter

from rest_framework import serializers
from django.utils import timezone

from planpals.collaboration.domain.entities import (
    ALLOWED_REACTIONS,
    AvailabilityStatus,
    WorkItemStatus,
    WorkItemType,
)
from planpals.collaboration.infrastructure.models import (
    AvailabilityOption,
    AvailabilityPoll,
    PlanComment,
    PlanWorkItem,
)


def user_summary(user):
    if user is None:
        return None
    return {
        'id': str(user.id),
        'username': user.username,
        'full_name': user.get_full_name() or user.username,
        'avatar_url': getattr(user, 'avatar_url', ''),
    }


class AvailabilityOptionInputSerializer(serializers.Serializer):
    label = serializers.CharField(max_length=120, required=False, allow_blank=True)
    start_at = serializers.DateTimeField()
    end_at = serializers.DateTimeField()

    def validate(self, attrs):
        if attrs['end_at'] <= attrs['start_at']:
            raise serializers.ValidationError({'end_at': 'Must be after start_at.'})
        return attrs


class AvailabilityPollCreateSerializer(serializers.Serializer):
    title = serializers.CharField(max_length=200)
    closes_at = serializers.DateTimeField(required=False, allow_null=True)
    options = AvailabilityOptionInputSerializer(many=True, min_length=2, max_length=20)


class AvailabilityVoteInputSerializer(serializers.Serializer):
    option_id = serializers.UUIDField()
    status = serializers.ChoiceField(choices=AvailabilityStatus.values())


class AvailabilityOptionSerializer(serializers.ModelSerializer):
    vote_counts = serializers.SerializerMethodField()
    current_user_vote = serializers.SerializerMethodField()

    class Meta:
        model = AvailabilityOption
        fields = ['id', 'label', 'start_at', 'end_at', 'vote_counts', 'current_user_vote']

    def get_vote_counts(self, obj):
        counts = Counter(vote.status for vote in obj.votes.all())
        return {status: counts.get(status, 0) for status in AvailabilityStatus.values()}

    def get_current_user_vote(self, obj):
        user_id = self.context.get('user_id')
        return next((vote.status for vote in obj.votes.all()
                     if str(vote.user_id) == str(user_id)), None)


class AvailabilityPollSerializer(serializers.ModelSerializer):
    created_by = serializers.SerializerMethodField()
    options = AvailabilityOptionSerializer(many=True)
    total_voters = serializers.SerializerMethodField()
    is_closed = serializers.SerializerMethodField()

    class Meta:
        model = AvailabilityPoll
        fields = [
            'id', 'group_id', 'title', 'created_by', 'closes_at', 'is_closed',
            'total_voters', 'options', 'created_at', 'updated_at',
        ]

    def get_created_by(self, obj):
        return user_summary(obj.created_by)

    def get_total_voters(self, obj):
        return len({vote.user_id for option in obj.options.all() for vote in option.votes.all()})

    def get_is_closed(self, obj):
        return obj.is_closed or bool(obj.closes_at and obj.closes_at <= timezone.now())


class WorkItemInputSerializer(serializers.Serializer):
    title = serializers.CharField(max_length=200, required=False)
    details = serializers.CharField(required=False, allow_blank=True)
    item_type = serializers.ChoiceField(choices=WorkItemType.values(), required=False)
    status = serializers.ChoiceField(choices=WorkItemStatus.values(), required=False)
    assignee_id = serializers.UUIDField(required=False, allow_null=True)
    activity_id = serializers.UUIDField(required=False, allow_null=True)
    due_at = serializers.DateTimeField(required=False, allow_null=True)
    order = serializers.IntegerField(required=False, min_value=0)


class PlanWorkItemSerializer(serializers.ModelSerializer):
    assignee = serializers.SerializerMethodField()
    created_by = serializers.SerializerMethodField()
    activity_title = serializers.CharField(source='activity.title', read_only=True)

    class Meta:
        model = PlanWorkItem
        fields = [
            'id', 'plan_id', 'activity_id', 'activity_title', 'title', 'details',
            'item_type', 'status', 'assignee', 'created_by', 'due_at',
            'completed_at', 'order', 'created_at', 'updated_at',
        ]

    def get_assignee(self, obj):
        return user_summary(obj.assignee)

    def get_created_by(self, obj):
        return user_summary(obj.created_by)


class CommentInputSerializer(serializers.Serializer):
    body = serializers.CharField(max_length=4000)
    activity_id = serializers.UUIDField(required=False, allow_null=True)
    parent_id = serializers.UUIDField(required=False, allow_null=True)
    mention_user_ids = serializers.ListField(
        child=serializers.UUIDField(), required=False, max_length=50
    )


class CommentUpdateSerializer(serializers.Serializer):
    body = serializers.CharField(max_length=4000)


class ReactionInputSerializer(serializers.Serializer):
    reaction = serializers.ChoiceField(
        choices=ALLOWED_REACTIONS, required=False, allow_null=True
    )


class PlanCommentSerializer(serializers.ModelSerializer):
    author = serializers.SerializerMethodField()
    pinned_by = serializers.SerializerMethodField()
    mentions = serializers.SerializerMethodField()
    reaction_counts = serializers.SerializerMethodField()
    current_user_reaction = serializers.SerializerMethodField()
    activity_title = serializers.CharField(source='activity.title', read_only=True)

    class Meta:
        model = PlanComment
        fields = [
            'id', 'plan_id', 'activity_id', 'activity_title', 'parent_id',
            'author', 'body', 'is_pinned', 'pinned_by', 'pinned_at', 'mentions',
            'reaction_counts', 'current_user_reaction', 'created_at', 'updated_at',
        ]

    def get_author(self, obj):
        return user_summary(obj.author)

    def get_pinned_by(self, obj):
        return user_summary(obj.pinned_by)

    def get_mentions(self, obj):
        return [user_summary(mention.user) for mention in obj.mentions.all()]

    def get_reaction_counts(self, obj):
        counts = Counter(reaction.reaction for reaction in obj.reactions.all())
        return {reaction: counts.get(reaction, 0) for reaction in ALLOWED_REACTIONS}

    def get_current_user_reaction(self, obj):
        user_id = self.context.get('user_id')
        return next((reaction.reaction for reaction in obj.reactions.all()
                     if str(reaction.user_id) == str(user_id)), None)


class ClonePlanSerializer(serializers.Serializer):
    title = serializers.CharField(max_length=200, required=False, allow_blank=True)
    start_date = serializers.DateTimeField()
    as_template = serializers.BooleanField(default=False)
