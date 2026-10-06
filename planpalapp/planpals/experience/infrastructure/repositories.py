from django.db import transaction
from django.db.models import Count, Prefetch, Q
from django.utils import timezone

from planpals.chat.infrastructure.models import ChatMessage, Conversation
from planpals.experience.application.repositories import ExperienceRepository
from planpals.experience.infrastructure.models import (
    GroupPoll,
    GroupPollOption,
    GroupPollVote,
    LiveLocationShare,
)
from planpals.groups.infrastructure.models import Group, GroupMembership
from planpals.plans.infrastructure.models import Plan


class DjangoExperienceRepository(ExperienceRepository):
    def is_group_member(self, group_id, user_id):
        return GroupMembership.objects.filter(
            group_id=group_id, user_id=user_id
        ).exists()

    def can_manage_group(self, group_id, user_id):
        return GroupMembership.objects.filter(
            group_id=group_id,
            user_id=user_id,
            role__in=[GroupMembership.ADMIN, GroupMembership.PLAN_CREATOR],
        ).exists()

    def list_group_polls(self, group_id, user_id):
        votes = GroupPollVote.objects.select_related('user').order_by('created_at')
        options = GroupPollOption.objects.annotate(
            vote_count=Count('votes')
        ).prefetch_related(Prefetch('votes', queryset=votes))
        return GroupPoll.objects.filter(group_id=group_id).select_related(
            'created_by'
        ).prefetch_related(Prefetch('options', queryset=options))

    @transaction.atomic
    def create_group_poll(self, group_id, user_id, data):
        options = data.pop('options')
        mutation_id = data.get('client_mutation_id')
        if mutation_id:
            existing = self.list_group_polls(group_id, user_id).filter(
                client_mutation_id=mutation_id
            ).first()
            if existing:
                existing._was_created = False
                return existing
        poll = GroupPoll.objects.create(
            group_id=group_id,
            created_by_id=user_id,
            **data,
        )
        GroupPollOption.objects.bulk_create([
            GroupPollOption(poll=poll, text=text, order=index)
            for index, text in enumerate(options)
        ])
        created = self.list_group_polls(group_id, user_id).get(id=poll.id)
        created._was_created = True
        return created

    def get_group_poll(self, poll_id, for_update=False):
        queryset = GroupPoll.objects
        if for_update:
            queryset = queryset.select_for_update()
        votes = GroupPollVote.objects.select_related('user').order_by('created_at')
        options = GroupPollOption.objects.annotate(
            vote_count=Count('votes')
        ).prefetch_related(Prefetch('votes', queryset=votes))
        return queryset.select_related('created_by', 'group').prefetch_related(
            Prefetch('options', queryset=options)
        ).filter(id=poll_id).first()

    @transaction.atomic
    def replace_poll_votes(self, poll, user_id, option_ids):
        GroupPollVote.objects.filter(poll=poll, user_id=user_id).delete()
        GroupPollVote.objects.bulk_create([
            GroupPollVote(poll=poll, option_id=option_id, user_id=user_id)
            for option_id in option_ids
        ])
        return self.list_group_polls(poll.group_id, user_id).get(id=poll.id)

    def close_poll(self, poll_id):
        GroupPoll.objects.filter(id=poll_id).update(
            is_closed=True, updated_at=timezone.now()
        )
        return self.get_group_poll(poll_id)

    def can_access_conversation(self, conversation_id, user_id):
        conversation = Conversation.objects.select_related('group').filter(
            id=conversation_id, is_active=True
        ).first()
        if conversation is None:
            return False
        if conversation.conversation_type == 'direct':
            return user_id in {conversation.user_a_id, conversation.user_b_id}
        return GroupMembership.objects.filter(
            group_id=conversation.group_id, user_id=user_id
        ).exists()

    def list_live_locations(self, conversation_id):
        now = timezone.now()
        LiveLocationShare.objects.filter(
            conversation_id=conversation_id,
            is_active=True,
            expires_at__lte=now,
        ).update(is_active=False, stopped_at=now)
        return LiveLocationShare.objects.filter(
            conversation_id=conversation_id,
            is_active=True,
            expires_at__gt=now,
        ).select_related('user')

    @transaction.atomic
    def create_live_location(self, conversation_id, user_id, data):
        # Serialize starts for the same conversation before checking idempotency.
        Conversation.objects.select_for_update().only('id').get(id=conversation_id)
        mutation_id = data.get('client_mutation_id')
        if mutation_id:
            existing = LiveLocationShare.objects.select_related('user').filter(
                conversation_id=conversation_id,
                user_id=user_id,
                client_mutation_id=mutation_id,
            ).first()
            if existing:
                existing._was_created = False
                return existing
        now = timezone.now()
        LiveLocationShare.objects.filter(
            conversation_id=conversation_id,
            user_id=user_id,
            is_active=True,
        ).update(is_active=False, stopped_at=now)
        created = LiveLocationShare.objects.create(
            conversation_id=conversation_id,
            user_id=user_id,
            consent_granted_at=now,
            **data,
        )
        created._was_created = True
        return created

    def get_live_location(self, share_id, for_update=False):
        queryset = LiveLocationShare.objects
        if for_update:
            queryset = queryset.select_for_update()
        return queryset.select_related('user', 'conversation').filter(
            id=share_id
        ).first()

    def update_live_location(self, share_id, data):
        LiveLocationShare.objects.filter(id=share_id).update(
            **data, updated_at=timezone.now()
        )
        return self.get_live_location(share_id)

    def expire_live_locations(self, now):
        return LiveLocationShare.objects.filter(
            is_active=True, expires_at__lte=now
        ).update(is_active=False, stopped_at=now)

    def global_search(self, user_id, query, types, limit):
        result = {'plans': [], 'groups': [], 'chats': []}
        if 'plans' in types:
            plans = Plan.objects.for_user(user_id).filter(
                Q(title__icontains=query) | Q(description__icontains=query)
            ).select_related('group').order_by('-updated_at')[:limit]
            result['plans'] = [
                {
                    'id': str(item.id),
                    'title': item.title,
                    'subtitle': item.group.name if item.group else item.description[:120],
                    'status': item.status,
                }
                for item in plans
            ]
        if 'groups' in types:
            groups = Group.objects.filter(
                memberships__user_id=user_id
            ).filter(
                Q(name__icontains=query) | Q(description__icontains=query)
            ).distinct().order_by('-updated_at')[:limit]
            result['groups'] = [
                {
                    'id': str(item.id),
                    'title': item.name,
                    'subtitle': item.description[:120],
                }
                for item in groups
            ]
        if 'chats' in types:
            matching_messages = ChatMessage.objects.filter(
                content__icontains=query
            ).order_by('-created_at')
            conversations = Conversation.objects.for_user(user_id).filter(
                Q(name__icontains=query)
                | Q(group__name__icontains=query)
                | Q(user_a__username__icontains=query)
                | Q(user_b__username__icontains=query)
                | Q(messages__content__icontains=query)
            ).distinct().select_related(
                'group', 'user_a', 'user_b'
            ).prefetch_related(
                Prefetch(
                    'messages',
                    queryset=matching_messages,
                    to_attr='search_matches',
                )
            ).order_by('-last_message_at')[:limit]
            result['chats'] = [self._conversation_result(item, user_id, query) for item in conversations]
        return result

    @staticmethod
    def _conversation_result(conversation, user_id, query):
        if conversation.conversation_type == 'group':
            title = conversation.name or conversation.group.name
        else:
            other = conversation.user_b if conversation.user_a_id == user_id else conversation.user_a
            title = other.get_full_name() or other.username
        matches = getattr(conversation, 'search_matches', ())
        matched = matches[0].content if matches else ''
        return {
            'id': str(conversation.id),
            'title': title,
            'subtitle': (matched or '')[:160],
            'conversation_type': conversation.conversation_type,
        }
