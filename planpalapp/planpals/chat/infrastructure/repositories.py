"""
Chat Infrastructure — Django ORM Repository Implementations
"""
import logging
from typing import Optional, Any, List, Dict
from uuid import UUID

from django.db.models import Q, Exists, OuterRef
from django.utils import timezone

from planpals.chat.domain.repositories import (
    ConversationRepository, ChatMessageRepository,
    FriendshipQueryRepository, GroupQueryRepository,
)
from planpals.chat.infrastructure.models import Conversation, ChatMessage, MessageReadStatus

logger = logging.getLogger(__name__)


class DjangoConversationRepository(ConversationRepository):
    """Django ORM implementation of ConversationRepository."""

    def get_by_id(self, conversation_id: UUID) -> Optional[Conversation]:
        try:
            return Conversation.objects.select_related('group', 'user_a', 'user_b').get(
                id=conversation_id,
            )
        except Conversation.DoesNotExist:
            return None

    def get_user_conversations(self, user_id: UUID) -> Any:
        return (
            Conversation.objects
            .for_user(user_id)
            .select_related('group', 'user_a', 'user_b')
            .with_last_message()
            .order_by('-last_message_at')
        )

    def search_conversations(self, user_id: UUID, query: str) -> Any:
        conversations = self.get_user_conversations(user_id)

        search_conditions = Q(name__icontains=query)
        search_conditions |= Q(group__name__icontains=query)
        search_conditions |= (
            Q(group__members__first_name__icontains=query)
            | Q(group__members__last_name__icontains=query)
            | Q(group__members__username__icontains=query)
        )
        search_conditions |= (
            Q(user_a__first_name__icontains=query)
            | Q(user_a__last_name__icontains=query)
            | Q(user_a__username__icontains=query)
            | Q(user_b__first_name__icontains=query)
            | Q(user_b__last_name__icontains=query)
            | Q(user_b__username__icontains=query)
        )

        return conversations.filter(search_conditions).distinct()

    def get_direct_conversation(self, user1_id: UUID, user2_id: UUID) -> Optional[Conversation]:
        return Conversation.objects.get_direct_conversation(user1_id, user2_id)

    def create_direct_conversation(self, user1_id: UUID, user2_id: UUID) -> Conversation:
        conv = Conversation(
            conversation_type='direct',
            user_a_id=user1_id,
            user_b_id=user2_id,
        )
        conv.save()
        return conv

    def create_group_conversation(self, group: Any) -> Conversation:
        conv = Conversation(
            conversation_type='group',
            group=group,
            name=f"Group Chat: {group.name}",
        )
        conv.save()
        return conv

    def get_group_conversation(self, group_id: UUID) -> Optional[Conversation]:
        try:
            return Conversation.objects.select_related('group').get(
                conversation_type='group',
                group_id=group_id,
            )
        except Conversation.DoesNotExist:
            return None

    def can_user_access(self, conversation_id: UUID, user_id: UUID) -> bool:
        try:
            conv = Conversation.objects.select_related('group').get(id=conversation_id)
        except Conversation.DoesNotExist:
            return False

        if conv.conversation_type == 'direct':
            return user_id in [conv.user_a_id, conv.user_b_id]
        elif conv.conversation_type == 'group' and conv.group:
            return conv.group.members.filter(id=user_id).exists()
        return False

    def update_last_message_time(self, conversation_id: UUID, timestamp: Any = None) -> None:
        if timestamp is None:
            timestamp = timezone.now()
        Conversation.objects.filter(id=conversation_id).update(last_message_at=timestamp)


class DjangoChatMessageRepository(ChatMessageRepository):
    """Django ORM implementation of ChatMessageRepository."""

    def get_by_id(self, message_id: UUID) -> Optional[ChatMessage]:
        try:
            return ChatMessage.objects.select_related(
                'sender', 'conversation', 'reply_to',
            ).get(id=message_id)
        except ChatMessage.DoesNotExist:
            return None

    def get_conversation_messages(
        self,
        conversation_id: UUID,
        limit: int = 50,
        before_id: UUID = None,
    ) -> Dict[str, Any]:
        qs = (
            ChatMessage.objects
            .filter(conversation_id=conversation_id, is_deleted=False)
            .select_related('sender', 'reply_to', 'reply_to__sender')
            .order_by('-created_at')
        )

        if before_id:
            try:
                cursor_msg = ChatMessage.objects.get(id=before_id)
                qs = qs.filter(created_at__lt=cursor_msg.created_at)
            except ChatMessage.DoesNotExist:
                pass

        messages = list(qs[:limit + 1])
        has_more = len(messages) > limit
        if has_more:
            messages = messages[:limit]

        return {
            'messages': list(reversed(messages)),
            'has_more': has_more,
            'next_cursor': str(messages[-1].id) if has_more and messages else None,
        }

    def create_message(self, conversation: Any, sender: Any, data: Dict) -> ChatMessage:
        message = ChatMessage(
            conversation=conversation,
            sender=sender,
            message_type=data.get('message_type', 'text'),
            content=data.get('content', ''),
        )

        # Optional fields
        if data.get('attachment'):
            message.attachment = data['attachment']
        if data.get('attachment_name'):
            message.attachment_name = data['attachment_name']
        if data.get('attachment_size'):
            message.attachment_size = data['attachment_size']
        if data.get('latitude') is not None:
            message.latitude = data['latitude']
        if data.get('longitude') is not None:
            message.longitude = data['longitude']
        if data.get('location_name'):
            message.location_name = data['location_name']
        if data.get('reply_to_id'):
            message.reply_to_id = data['reply_to_id']

        message.save()
        return message

    def soft_delete(self, message_id: UUID) -> bool:
        try:
            message = ChatMessage.objects.get(id=message_id)
            message.soft_delete()
            return True
        except ChatMessage.DoesNotExist:
            return False

    def update_content(self, message_id: UUID, new_content: str) -> ChatMessage:
        message = ChatMessage.objects.get(id=message_id)
        message.content = new_content
        message.is_edited = True
        message.save(update_fields=['content', 'is_edited', 'updated_at'])
        return message

    def mark_as_read(self, message_ids: List[UUID], user_id: UUID) -> int:
        read_statuses = [
            MessageReadStatus(message_id=msg_id, user_id=user_id)
            for msg_id in message_ids
        ]
        result = MessageReadStatus.objects.bulk_create(read_statuses, ignore_conflicts=True)
        return len(result)

    def bulk_mark_read_for_conversation(
        self, conversation_id: UUID, user_id: UUID, up_to_message_id: UUID = None
    ) -> int:
        messages = ChatMessage.objects.filter(
            conversation_id=conversation_id, is_deleted=False,
        ).exclude(sender_id=user_id)

        if up_to_message_id:
            try:
                up_to_msg = ChatMessage.objects.get(id=up_to_message_id)
                messages = messages.filter(created_at__lte=up_to_msg.created_at)
            except ChatMessage.DoesNotExist:
                pass

        unread_ids = list(
            messages.exclude(
                read_statuses__user_id=user_id,
            ).values_list('id', flat=True)
        )

        if unread_ids:
            read_statuses = [
                MessageReadStatus(message_id=mid, user_id=user_id)
                for mid in unread_ids
            ]
            MessageReadStatus.objects.bulk_create(read_statuses, ignore_conflicts=True)

        return len(unread_ids)

    def get_unread_count(self, conversation_id: UUID, user_id: UUID) -> int:
        return (
            ChatMessage.objects
            .filter(conversation_id=conversation_id, is_deleted=False)
            .exclude(sender_id=user_id)
            .exclude(
                Exists(
                    MessageReadStatus.objects.filter(
                        message=OuterRef('pk'),
                        user_id=user_id,
                    )
                )
            )
            .count()
        )

    def get_valid_reply_message(
        self, message_id: UUID, conversation_id: UUID
    ) -> Optional[ChatMessage]:
        try:
            return ChatMessage.objects.get(
                id=message_id,
                conversation_id=conversation_id,
                is_deleted=False,
            )
        except ChatMessage.DoesNotExist:
            return None


class DjangoChatFriendshipQueryRepository(FriendshipQueryRepository):
    """Cross-context friendship query for chat."""

    def are_friends(self, user1_id: UUID, user2_id: UUID) -> bool:
        from planpals.auth.infrastructure.models import Friendship
        return Friendship.are_friends(user1_id, user2_id)


class DjangoChatGroupQueryRepository(GroupQueryRepository):
    """Cross-context group query for chat."""

    def get_by_id(self, group_id: UUID) -> Optional[Any]:
        from planpals.groups.infrastructure.models import Group
        try:
            return Group.objects.get(id=group_id)
        except Group.DoesNotExist:
            return None

    def is_member(self, group_id: UUID, user_id: UUID) -> bool:
        from planpals.groups.infrastructure.models import Group
        try:
            group = Group.objects.get(id=group_id)
            return group.members.filter(id=user_id).exists()
        except Group.DoesNotExist:
            return False
