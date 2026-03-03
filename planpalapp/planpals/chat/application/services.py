import datetime
import logging
from typing import Dict, List, Tuple, Any

from planpals.shared.base_service import BaseService

# Commands & factories — thin delegation layer
from planpals.chat.application.commands import (
    EditMessageCommand,
    DeleteMessageCommand,
    MarkMessagesReadCommand,
)
from planpals.chat.application import factories as chat_factories

logger = logging.getLogger(__name__)


class ConversationService(BaseService):
    
    @classmethod
    def create_message(cls, conversation, sender, 
                      validated_data: Dict[str, Any]):
        message_type = validated_data.get('message_type', 'text')
        content = validated_data.get('content', '')
        attachment = validated_data.get('attachment')
        attachment_name = validated_data.get('attachment_name', '')
        attachment_size = validated_data.get('attachment_size')
        reply_to_id = validated_data.get('reply_to_id')
        latitude = validated_data.get('latitude')
        longitude = validated_data.get('longitude')
        location_name = validated_data.get('location_name', '')
        
        message_repo = chat_factories.get_message_repo()
        conversation_repo = chat_factories.get_conversation_repo()
        
        # Validate reply_to
        reply_to = None
        if reply_to_id:
            reply_to = message_repo.get_valid_reply_message(reply_to_id, conversation.id)
            if not reply_to:
                raise ValueError("Reply message not found in this conversation")
        
        if attachment:
            if isinstance(attachment, str):
                attachment = attachment.strip()
                if cls.is_local_path(attachment):
                    raise ValueError(
                        "Local file paths are not allowed. Please upload the file via multipart request."
                    )
                # Allow Cloudinary URLs/public_ids
            elif hasattr(attachment, 'read'):
                # File upload - will be handled by CloudinaryField on save
                pass
            else:
                raise ValueError("Attachment must be a file upload or valid URL/public_id")
        
        data = {
            'message_type': message_type,
            'content': content,
            'attachment': attachment,
            'attachment_name': attachment_name,
            'attachment_size': attachment_size,
            'reply_to_id': str(reply_to_id) if reply_to_id else None,
            'latitude': latitude,
            'longitude': longitude,
            'location_name': location_name,
        }
        
        message = message_repo.create_message(conversation, sender, data)
        conversation_repo.update_last_message_time(conversation.id)
        
        # Publish via infrastructure publishers
        try:
            chat_factories.get_realtime_publisher().send_message(message)
        except Exception as e:
            cls.log_error("Error sending realtime message", e)
        
        try:
            chat_factories.get_push_publisher().send_notification(message)
        except Exception as e:
            cls.log_error("Error sending push notification", e)
        
        cls.log_operation("message_created", {
            'conversation_id': str(conversation.id),
            'message_id': str(message.id),
            'sender_id': str(sender.id) if sender else None,
            'message_type': message_type
        })
        
        return message
    
    @classmethod
    def get_user_conversations(cls, user):
        return chat_factories.get_conversation_repo().get_user_conversations(user.id)
    
    @classmethod
    def search_user_conversations(cls, user, query: str):
        """Search conversations by name, participant names, or group names"""
        if not query or not query.strip():
            return cls.get_user_conversations(user)
        
        return chat_factories.get_conversation_repo().search_conversations(user.id, query.strip().lower())
    
    @classmethod
    def get_or_create_direct_conversation(cls, user1, user2) -> Tuple[Any, bool]:
        if user1.id == user2.id:
            raise ValueError("Cannot create conversation with yourself")
        
        friendship_repo = chat_factories.get_friendship_query_repo()
        if not friendship_repo.are_friends(user1.id, user2.id):
            raise ValueError("Users must be friends to start a conversation")
        
        conversation_repo = chat_factories.get_conversation_repo()
        
        # Check for existing conversation
        existing_conv = conversation_repo.get_direct_conversation(user1.id, user2.id)
        if existing_conv:
            return existing_conv, False
        
        conversation = conversation_repo.create_direct_conversation(user1.id, user2.id)
        
        cls.log_operation("conversation_created", {
            'conversation_id': str(conversation.id),
            'type': 'direct',
            'participants': [str(user1.id), str(user2.id)]
        })
        
        return conversation, True
    
    @classmethod 
    def create_direct_conversation(cls, user1, user2):
        if user1.id == user2.id:
            raise ValueError("Cannot create conversation with same user")

        return chat_factories.get_conversation_repo().create_direct_conversation(user1.id, user2.id)
    
    @classmethod
    def get_or_create_group_conversation(cls, group) -> Tuple[Any, bool]:
        conversation_repo = chat_factories.get_conversation_repo()
        
        existing = conversation_repo.get_group_conversation(group.id)
        if existing:
            return existing, False
        
        conversation = conversation_repo.create_group_conversation(group)
        
        cls.log_operation("conversation_created", {
            'conversation_id': str(conversation.id),
            'type': 'group',
            'group_id': str(group.id)
        })
        
        return conversation, True

    

    @classmethod
    def get_conversation_messages(cls, user, conversation_id: str, 
                                limit: int = 50, before_id: str = None) -> Dict[str, Any]:
        conversation_repo = chat_factories.get_conversation_repo()
        message_repo = chat_factories.get_message_repo()
        
        conversation = conversation_repo.get_by_id(conversation_id)
        if not conversation:
            raise ValueError("Conversation not found")
        
        if not conversation_repo.can_user_access(conversation_id, user.id):
            raise ValueError("Access denied to this conversation")
        
        return message_repo.get_conversation_messages(
            conversation_id=conversation_id,
            limit=limit,
            before_id=before_id,
        )
    

    @classmethod
    def mark_messages_read(cls, user, conversation_id: str, message_ids: List[str]) -> Tuple[bool, str]:
        conversation_repo = chat_factories.get_conversation_repo()
        message_repo = chat_factories.get_message_repo()
        
        if not conversation_repo.can_user_access(conversation_id, user.id):
            return False, "Access denied to this conversation"
        
        try:
            count = message_repo.mark_as_read(message_ids, user.id)
            
            if hasattr(user, 'clear_unread_cache'):
                user.clear_unread_cache()
            
            cls.log_operation("messages_marked_read", {
                'user_id': str(user.id),
                'conversation_id': str(conversation_id),
                'message_count': count
            })
            
            return True, f"Marked {count} messages as read"
        except Exception as e:
            return False, "Failed to mark messages as read"
    
    @classmethod
    def mark_as_read_for_user(cls, conversation, user, up_to_message=None):
        message_repo = chat_factories.get_message_repo()
        up_to_id = up_to_message.id if up_to_message else None
        count = message_repo.bulk_mark_read_for_conversation(conversation.id, user.id, up_to_id)
        
        if hasattr(user, 'clear_unread_cache') and count > 0:
            user.clear_unread_cache()
        
        return count
    
    @classmethod
    def get_unread_count_for_user(cls, conversation, user):
        return chat_factories.get_message_repo().get_unread_count(conversation.id, user.id)
    

    @classmethod
    def update_last_message_time(cls, conversation, timestamp=None):
        if timestamp is None:
            timestamp = datetime.datetime.now(datetime.timezone.utc)
        chat_factories.get_conversation_repo().update_last_message_time(conversation.id, timestamp)
    
    @classmethod
    def _can_user_access_conversation(cls, user, conversation) -> bool:
        return chat_factories.get_conversation_repo().can_user_access(conversation.id, user.id)


class ChatService(BaseService):
    
    @classmethod
    def send_message(cls, sender, group, **validated_data) -> 'ChatMessage':

        # Get or create group conversation
        conversation, created = ConversationService.get_or_create_group_conversation(group)
        
        # Delegate to canonical message creation
        return ConversationService.create_message(
            conversation=conversation,
            sender=sender,
            validated_data=validated_data
        )
    
    @classmethod
    def send_direct_message(cls, sender, recipient, **validated_data) -> 'ChatMessage':

        conversation, created = ConversationService.get_or_create_direct_conversation(sender, recipient)
        
        return ConversationService.create_message(
            conversation=conversation,
            sender=sender,
            validated_data=validated_data
        )
    
    @classmethod
    def create_system_message(cls, conversation=None, group=None, content: str = "") -> 'ChatMessage':
        if conversation is None and group is None:
            raise ValueError("Either conversation or group must be provided")
        
        if group is not None:
            conversation, created = ConversationService.get_or_create_group_conversation(group)
        
        validated_data = {
            'message_type': 'system',
            'content': content
        }
        
        return ConversationService.create_message(
            conversation=conversation,
            sender=None,  # System messages have no sender
            validated_data=validated_data
        )
    
    @classmethod
    def get_group_messages(cls, user, group_id: str, limit: int = 50, before_id: str = None) -> Dict[str, Any]:
        group_query_repo = chat_factories.get_group_query_repo()
        
        group = group_query_repo.get_by_id(group_id)
        if not group:
            raise ValueError("Group not found")
        
        if not group_query_repo.is_member(group_id, user.id):
            raise ValueError("Group not found or access denied")
        
        # Get or create group conversation
        conversation, created = ConversationService.get_or_create_group_conversation(group)
        
        # Use conversation service
        return ConversationService.get_conversation_messages(
            user=user,
            conversation_id=str(conversation.id),
            limit=limit,
            before_id=before_id
        )
    
    @classmethod
    def edit_message(cls, message, user, new_content: str) -> Tuple[bool, str]:
        """Delegate to EditMessageHandler."""
        cmd = EditMessageCommand(
            message_id=message.id,
            editor_id=user.id,
            new_content=new_content,
        )
        handler = chat_factories.get_edit_message_handler()
        success, msg = handler.handle(cmd)

        if success:
            cls.log_operation("message_edited", {
                'message_id': str(message.id),
                'editor': str(user.id)
            })

        return success, msg
    
    @classmethod
    def delete_message(cls, message, user) -> Tuple[bool, str]:
        """Delegate to DeleteMessageHandler."""
        cmd = DeleteMessageCommand(
            message_id=message.id,
            deleted_by_id=user.id,
        )
        handler = chat_factories.get_delete_message_handler()
        success, msg = handler.handle(cmd)

        if success:
            cls.log_operation("message_deleted", {
                'message_id': str(message.id),
                'deleted_by': str(user.id),
            })

        return success, msg
    
    @classmethod
    def get_unread_count(cls, user, group=None) -> int:
        if group:
            conversation, created = ConversationService.get_or_create_group_conversation(group)
            return ConversationService.get_unread_count_for_user(conversation, user)
        else:
            return getattr(user, 'unread_messages_count', 0)
    
    @classmethod
    def mark_messages_as_read(cls, user, group) -> None:
        conversation, created = ConversationService.get_or_create_group_conversation(group)
        ConversationService.mark_as_read_for_user(conversation, user)
        
        cls.log_operation("messages_marked_read", {
            'user_id': str(user.id),
            'group_id': str(group.id),
            'timestamp': datetime.datetime.now(datetime.timezone.utc).isoformat()
        })
