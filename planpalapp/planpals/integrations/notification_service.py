from typing import Dict, List, Optional, Any, Tuple
from django.conf import settings
from django.core.mail import send_mail
from django.template.loader import render_to_string
from django.core.cache import cache
from django.utils import timezone
from .base_service import BaseService
import json
import requests
import logging
from datetime import timedelta

logger = logging.getLogger(__name__)

class NotificationService(BaseService):
    """Enhanced service for sending push notifications and email with performance optimizations"""
    
    def __init__(self):
        super().__init__()
        self.fcm_server_key = getattr(settings, 'FCM_SERVER_KEY', None)
        self.fcm_url = "https://fcm.googleapis.com/fcm/send"
        self.batch_size = getattr(settings, 'FCM_BATCH_SIZE', 500)  # Max tokens per batch
        self.rate_limit_window = 3600  # 1 hour in seconds
        self.max_notifications_per_hour = getattr(settings, 'FCM_RATE_LIMIT', 1000)
    
    def validate_config(self) -> bool:
        """Kiểm tra cấu hình notification"""
        if not self.fcm_server_key:
            self.log_error("FCM Server Key không được cấu hình")
            return False
        return True
    
    def check_rate_limit(self, user_id: str = None) -> bool:
        """Check if we're within rate limits for notifications"""
        cache_key = f"fcm_rate_limit:{user_id or 'global'}"
        current_count = cache.get(cache_key, 0)
        
        if current_count >= self.max_notifications_per_hour:
            logger.warning(f"Rate limit exceeded for {user_id or 'global'}: {current_count}")
            return False
        
        # Increment counter with expiry
        cache.set(cache_key, current_count + 1, self.rate_limit_window)
        return True
    
    def send_push_notification_batch(self, fcm_tokens: List[str], title: str, 
                                   body: str, data: Optional[Dict[str, Any]] = None) -> Tuple[int, int]:
        """
        Send push notifications in batches for better performance
        
        Returns:
            Tuple[success_count, total_count]
        """
        if not self.validate_config():
            return 0, len(fcm_tokens)
        
        if not fcm_tokens:
            return 0, 0
        
        # Check global rate limit
        if not self.check_rate_limit():
            logger.warning("Global rate limit exceeded, skipping notifications")
            return 0, len(fcm_tokens)
        
        headers = {
            'Authorization': f'key={self.fcm_server_key}',
            'Content-Type': 'application/json',
        }
        
        success_count = 0
        total_count = len(fcm_tokens)
        
        # Process tokens in batches
        for i in range(0, len(fcm_tokens), self.batch_size):
            batch_tokens = fcm_tokens[i:i + self.batch_size]
            
            # Use multicast for better performance when sending to multiple devices
            if len(batch_tokens) > 1:
                payload = {
                    'registration_ids': batch_tokens,
                    'notification': {
                        'title': title,
                        'body': body,
                        'sound': 'default',
                        'badge': 1
                    },
                    'priority': 'high',
                    'content_available': True
                }
            else:
                payload = {
                    'to': batch_tokens[0],
                    'notification': {
                        'title': title,
                        'body': body,
                        'sound': 'default',
                        'badge': 1
                    },
                    'priority': 'high',
                    'content_available': True
                }
            
            if data:
                payload['data'] = {k: str(v) for k, v in data.items()}  # FCM requires string values
            
            try:
                response = requests.post(
                    self.fcm_url,
                    headers=headers,
                    data=json.dumps(payload),
                    timeout=10  # Add timeout
                )
                
                if response.status_code == 200:
                    result = response.json()
                    if len(batch_tokens) > 1:
                        # Multicast response
                        batch_success = result.get('success', 0)
                        success_count += batch_success
                        
                        # Handle failed tokens for cleanup
                        if 'results' in result:
                            self._handle_failed_tokens(batch_tokens, result['results'])
                    else:
                        # Single token response
                        if result.get('success', 0) > 0:
                            success_count += 1
                        else:
                            self._handle_failed_token(batch_tokens[0], result)
                else:
                    logger.error(f"FCM HTTP error {response.status_code}: {response.text}")
                    
            except requests.exceptions.Timeout:
                logger.error(f"FCM request timeout for batch of {len(batch_tokens)} tokens")
            except Exception as e:
                logger.error(f"FCM request failed for batch of {len(batch_tokens)} tokens: {e}")
        
        logger.info(f"FCM batch send completed: {success_count}/{total_count} successful")
        return success_count, total_count
    
    def _handle_failed_tokens(self, tokens: List[str], results: List[Dict]):
        """Handle failed token results from multicast"""
        for i, result in enumerate(results):
            if 'error' in result:
                if i < len(tokens):
                    self._handle_failed_token(tokens[i], result)
    
    def _handle_failed_token(self, token: str, result: Dict):
        """Handle individual failed token - could implement token cleanup here"""
        error = result.get('error', 'unknown')
        if error in ['NotRegistered', 'InvalidRegistration']:
            # Could implement automatic token cleanup
            logger.info(f"Invalid FCM token detected: {token[:10]}... (error: {error})")
        else:
            logger.warning(f"FCM send failed for token {token[:10]}...: {error}")
    
    def send_push_notification(self, fcm_tokens: List[str], title: str, 
                             body: str, data: Optional[Dict[str, Any]] = None) -> bool:
        """Legacy method for backward compatibility - delegates to batch method"""
        success_count, total_count = self.send_push_notification_batch(fcm_tokens, title, body, data)
        return success_count > 0
    
    def send_group_notification(self, group_id: str, title: str, body: str, 
                              exclude_user_id: Optional[str] = None,
                              data: Optional[Dict[str, Any]] = None) -> bool:
        """
        Gửi thông báo cho tất cả thành viên trong group với batching và rate limiting
        """
        from ..models import Group  # Import ở đây để tránh circular import
        
        try:
            group = Group.objects.prefetch_related('members').get(id=group_id)
            members = group.members.all()
            
            if exclude_user_id:
                members = members.exclude(id=exclude_user_id)
            
            # Lấy FCM tokens và IDs của các thành viên
            fcm_tokens = []
            member_ids = []
            for member in members:
                if hasattr(member, 'fcm_token') and member.fcm_token:
                    fcm_tokens.append(member.fcm_token)
                    member_ids.append(str(member.id))
            
            if not fcm_tokens:
                logger.info(f"Không có FCM token nào cho group {group_id}")
                return True
            
            # Check individual rate limits
            valid_tokens = []
            for i, token in enumerate(fcm_tokens):
                if self.check_rate_limit(member_ids[i]):
                    valid_tokens.append(token)
            
            if not valid_tokens:
                logger.warning(f"All users rate limited for group {group_id}")
                return False
            
            # Thêm thông tin group vào data
            notification_data = {
                'type': 'group_notification',
                'group_id': group_id,
                'group_name': group.name,
                **(data or {})
            }
            
            success_count, total_count = self.send_push_notification_batch(
                valid_tokens, title, body, notification_data
            )
            
            logger.info(f"Group {group_id} notifications: {success_count}/{total_count} delivered")
            return success_count > 0
            
        except Group.DoesNotExist:
            logger.error(f"Group {group_id} không tồn tại")
            return False
        except Exception as e:
            logger.error(f"Lỗi khi gửi group notification: {e}")
            return False
    
    def send_plan_notification(self, plan_id: str, title: str, body: str,
                             exclude_user_id: Optional[str] = None,
                             data: Optional[Dict[str, Any]] = None) -> bool:
        """
        Gửi thông báo cho tất cả thành viên trong plan với batching và rate limiting
        """
        from ..models import Plan  # Import ở đây để tránh circular import
        
        try:
            plan = Plan.objects.select_related('created_by').prefetch_related('members').get(id=plan_id)
            
            # Lấy FCM tokens của các thành viên
            fcm_tokens = []
            member_ids = []
            
            # Add plan creator
            if plan.created_by and plan.created_by.id != exclude_user_id:
                if hasattr(plan.created_by, 'fcm_token') and plan.created_by.fcm_token:
                    fcm_tokens.append(plan.created_by.fcm_token)
                    member_ids.append(str(plan.created_by.id))
            
            # Add plan members
            for member in plan.members.all():
                if member.id != exclude_user_id:
                    if hasattr(member, 'fcm_token') and member.fcm_token:
                        fcm_tokens.append(member.fcm_token)
                        member_ids.append(str(member.id))
            
            if not fcm_tokens:
                logger.info(f"Không có FCM token nào cho plan {plan_id}")
                return True
            
            # Check individual rate limits
            valid_tokens = []
            for i, token in enumerate(fcm_tokens):
                if self.check_rate_limit(member_ids[i]):
                    valid_tokens.append(token)
            
            if not valid_tokens:
                logger.warning(f"All users rate limited for plan {plan_id}")
                return False
            
            # Thêm thông tin plan vào data
            notification_data = {
                'type': 'plan_notification',
                'plan_id': plan_id,
                'plan_title': getattr(plan, 'title', getattr(plan, 'name', 'Unnamed Plan')),
                **(data or {})
            }
            
            success_count, total_count = self.send_push_notification_batch(
                valid_tokens, title, body, notification_data
            )
            
            logger.info(f"Plan {plan_id} notifications: {success_count}/{total_count} delivered")
            return success_count > 0
            
        except Plan.DoesNotExist:
            logger.error(f"Plan {plan_id} không tồn tại")
            return False
        except Exception as e:
            logger.error(f"Lỗi khi gửi plan notification: {e}")
            return False
    
    def send_email_notification(self, to_emails: List[str], subject: str,
                              template_name: str, context: Dict[str, Any],
                              from_email: Optional[str] = None) -> bool:
        """
        Gửi email notification
        
        Args:
            to_emails: Danh sách email người nhận
            subject: Tiêu đề email
            template_name: Tên template email
            context: Dữ liệu cho template
            from_email: Email người gửi
        """
        if not to_emails:
            self.log_error("Danh sách email trống")
            return False
        
        try:
            # Render email content từ template
            html_message = render_to_string(f'emails/{template_name}.html', context)
            plain_message = render_to_string(f'emails/{template_name}.txt', context)
            
            from_email = from_email or settings.DEFAULT_FROM_EMAIL
            
            send_mail(
                subject=subject,
                message=plain_message,
                from_email=from_email,
                recipient_list=to_emails,
                html_message=html_message,
                fail_silently=False
            )
            
            self.log_info(f"Gửi email thành công đến {len(to_emails)} địa chỉ")
            return True
            
        except Exception as e:
            self.log_error("Lỗi khi gửi email", e)
            return False
    
    def notify_new_message(self, group_id: str, sender_name: str, 
                         message_preview: str, sender_id: str) -> bool:
        """Thông báo tin nhắn mới trong group"""
        title = f"Tin nhắn mới từ {sender_name}"
        body = message_preview[:100] + "..." if len(message_preview) > 100 else message_preview
        
        data = {
            'action': 'new_message',
            'sender_id': sender_id,
            'message_preview': message_preview
        }
        
        return self.send_group_notification(group_id, title, body, sender_id, data)
    
    def notify_plan_update(self, plan_id: str, updater_name: str, 
                         update_type: str, updater_id: str) -> bool:
        """Thông báo cập nhật plan"""
        title = f"Kế hoạch được cập nhật"
        
        if update_type == 'activity_added':
            body = f"{updater_name} đã thêm hoạt động mới"
        elif update_type == 'activity_updated':
            body = f"{updater_name} đã cập nhật hoạt động"
        elif update_type == 'activity_completed':
            body = f"{updater_name} đã hoàn thành một hoạt động"
        elif update_type == 'activity_deleted':
            body = f"{updater_name} đã xóa một hoạt động"
        elif update_type == 'plan_updated':
            body = f"{updater_name} đã cập nhật thông tin kế hoạch"
        elif update_type == 'status_changed':
            body = f"Trạng thái kế hoạch đã được cập nhật"
        else:
            body = f"{updater_name} đã cập nhật kế hoạch"
        
        data = {
            'action': 'plan_updated',
            'updater_id': updater_id,
            'update_type': update_type
        }
        
        return self.send_plan_notification(plan_id, title, body, updater_id, data)
    
    def notify_activity_created(self, plan_id: str, activity_title: str, 
                              creator_name: str, creator_id: str) -> bool:
        """Thông báo hoạt động mới được tạo"""
        title = f"Hoạt động mới được thêm"
        body = f"{creator_name} đã thêm hoạt động '{activity_title}'"
        
        data = {
            'action': 'activity_created',
            'activity_title': activity_title,
            'creator_id': creator_id
        }
        
        return self.send_plan_notification(plan_id, title, body, creator_id, data)
    
    def notify_activity_updated(self, plan_id: str, activity_title: str,
                              updater_name: str, updater_id: str, 
                              updated_fields: List[str] = None) -> bool:
        """Thông báo hoạt động được cập nhật"""
        title = f"Hoạt động được cập nhật"
        
        if updated_fields and len(updated_fields) == 1:
            field_name = updated_fields[0]
            if field_name == 'start_time':
                body = f"{updater_name} đã thay đổi thời gian bắt đầu của '{activity_title}'"
            elif field_name == 'location_name':
                body = f"{updater_name} đã thay đổi địa điểm của '{activity_title}'"
            elif field_name == 'description':
                body = f"{updater_name} đã cập nhật mô tả của '{activity_title}'"
            else:
                body = f"{updater_name} đã cập nhật '{activity_title}'"
        else:
            body = f"{updater_name} đã cập nhật hoạt động '{activity_title}'"
        
        data = {
            'action': 'activity_updated',
            'activity_title': activity_title,
            'updater_id': updater_id,
            'updated_fields': updated_fields or []
        }
        
        return self.send_plan_notification(plan_id, title, body, updater_id, data)
    
    def notify_activity_completed(self, plan_id: str, activity_title: str,
                                 completer_name: str, completer_id: str) -> bool:
        """Thông báo hoạt động được hoàn thành"""
        title = f"Hoạt động hoàn thành"
        body = f"{completer_name} đã hoàn thành '{activity_title}'"
        
        data = {
            'action': 'activity_completed',
            'activity_title': activity_title,
            'completer_id': completer_id
        }
        
        return self.send_plan_notification(plan_id, title, body, completer_id, data)
    
    def notify_activity_deleted(self, plan_id: str, activity_title: str,
                               deleter_name: str, deleter_id: str) -> bool:
        """Thông báo hoạt động bị xóa"""
        title = f"Hoạt động đã bị xóa"
        body = f"{deleter_name} đã xóa hoạt động '{activity_title}'"
        
        data = {
            'action': 'activity_deleted',
            'activity_title': activity_title,
            'deleter_id': deleter_id
        }
        
        return self.send_plan_notification(plan_id, title, body, deleter_id, data)
    
    def notify_plan_status_changed(self, plan_id: str, plan_title: str,
                                  old_status: str, new_status: str,
                                  changed_by: str = None, changed_by_id: str = None) -> bool:
        """Thông báo thay đổi trạng thái kế hoạch"""
        title = f"Trạng thái kế hoạch thay đổi"
        
        status_names = {
            'upcoming': 'sắp bắt đầu',
            'ongoing': 'đang diễn ra', 
            'completed': 'đã hoàn thành',
            'cancelled': 'đã hủy'
        }
        
        old_status_vn = status_names.get(old_status, old_status)
        new_status_vn = status_names.get(new_status, new_status)
        
        if changed_by:
            body = f"{changed_by} đã thay đổi trạng thái kế hoạch '{plan_title}' từ {old_status_vn} thành {new_status_vn}"
        else:
            body = f"Kế hoạch '{plan_title}' đã thay đổi từ {old_status_vn} thành {new_status_vn}"
        
        data = {
            'action': 'status_changed',
            'plan_title': plan_title,
            'old_status': old_status,
            'new_status': new_status,
            'changed_by_id': changed_by_id
        }
        
        return self.send_plan_notification(plan_id, title, body, changed_by_id, data)
    
    def notify_invitation(self, user_id: str, inviter_name: str, 
                        invitation_type: str, item_name: str) -> bool:
        """Thông báo lời mời tham gia group/plan với rate limiting"""
        from ..models import User  # Import ở đây để tránh circular import
        
        try:
            user = User.objects.get(id=user_id)
            if not hasattr(user, 'fcm_token') or not user.fcm_token:
                return False
            
            # Check rate limit for this user
            if not self.check_rate_limit(str(user_id)):
                logger.warning(f"Rate limit exceeded for user {user_id}")
                return False
            
            title = "Lời mời mới"
            if invitation_type == 'group':
                body = f"{inviter_name} đã mời bạn tham gia nhóm '{item_name}'"
            else:
                body = f"{inviter_name} đã mời bạn tham gia kế hoạch '{item_name}'"
            
            data = {
                'action': 'invitation',
                'invitation_type': invitation_type,
                'item_name': item_name,
                'inviter_name': inviter_name
            }
            
            success_count, total_count = self.send_push_notification_batch(
                [user.fcm_token], title, body, data
            )
            return success_count > 0
            
        except User.DoesNotExist:
            logger.error(f"User {user_id} không tồn tại")
            return False
        except Exception as e:
            logger.error(f"Lỗi khi gửi invitation notification: {e}")
            return False

    def notify_friend_request(self, user_id: str, requester_name: str) -> bool:
        """Thông báo lời mời kết bạn với rate limiting"""
        from ..models import User  # Import ở đây để tránh circular import
        
        try:
            user = User.objects.get(id=user_id)
            if not hasattr(user, 'fcm_token') or not user.fcm_token:
                return False
            
            # Check rate limit for this user
            if not self.check_rate_limit(str(user_id)):
                logger.warning(f"Rate limit exceeded for user {user_id}")
                return False
            
            title = "Lời mời kết bạn"
            body = f"{requester_name} đã gửi lời mời kết bạn"
            
            data = {
                'action': 'friend_request',
                'requester_name': requester_name,
                'type': 'friend_request'
            }
            
            success_count, total_count = self.send_push_notification_batch(
                [user.fcm_token], title, body, data
            )
            return success_count > 0
            
        except User.DoesNotExist:
            logger.error(f"User {user_id} không tồn tại")
            return False
        except Exception as e:
            logger.error(f"Lỗi khi gửi friend request notification: {e}")
            return False

    def notify_friend_request_accepted(self, user_id: str, accepter_name: str) -> bool:
        """Thông báo lời mời kết bạn được chấp nhận"""
        from ..models import User  # Import ở đây để tránh circular import
        
        try:
            user = User.objects.get(id=user_id)
            if not hasattr(user, 'fcm_token') or not user.fcm_token:
                return False
            
            # Check rate limit for this user
            if not self.check_rate_limit(str(user_id)):
                logger.warning(f"Rate limit exceeded for user {user_id}")
                return False
            
            title = "Kết bạn thành công"
            body = f"{accepter_name} đã chấp nhận lời mời kết bạn của bạn"
            
            data = {
                'action': 'friend_request_accepted',
                'accepter_name': accepter_name,
                'type': 'friend_request_accepted'
            }
            
            success_count, total_count = self.send_push_notification_batch(
                [user.fcm_token], title, body, data
            )
            return success_count > 0
            
        except User.DoesNotExist:
            logger.error(f"User {user_id} không tồn tại")
            return False
        except Exception as e:
            logger.error(f"Lỗi khi gửi friend request accepted notification: {e}")
            return False

    def send_to_user(self, user_id: str, title: str, body: str,
                    data: Optional[Dict[str, Any]] = None) -> bool:
        """
        Gửi notification cho một user cụ thể với rate limiting
        """
        try:
            from ..models import User
            user = User.objects.get(id=user_id)
            
            if not hasattr(user, 'fcm_token') or not user.fcm_token:
                logger.info(f"User {user_id} không có FCM token")
                return True
            
            # Check individual rate limit
            if not self.check_rate_limit(str(user_id)):
                logger.warning(f"Rate limit exceeded for user {user_id}")
                return False
            
            notification_data = {
                'user_id': str(user_id),
                'type': 'user_notification',
                **(data or {})
            }
            
            success_count, total_count = self.send_push_notification_batch(
                [user.fcm_token], title, body, notification_data
            )
            
            return success_count > 0
            
        except Exception as e:
            logger.error(f"Lỗi khi gửi notification cho user {user_id}: {e}")
            return False
    
    def get_statistics(self) -> Dict[str, Any]:
        """Get notification delivery statistics for monitoring and debugging"""
        try:
            stats = {
                'rate_limit_window_hours': self.rate_limit_window / 3600,
                'max_notifications_per_hour': self.max_notifications_per_hour,
                'batch_size': self.batch_size,
                'fcm_configured': bool(self.fcm_server_key),
                'timestamp': timezone.now().isoformat(),
                'fcm_url': self.fcm_url
            }
            
            # Add basic health check
            stats['health_status'] = 'healthy' if self.validate_config() else 'misconfigured'
            
            return stats
            
        except Exception as e:
            logger.error(f"Error getting notification statistics: {e}")
            return {'error': str(e), 'timestamp': timezone.now().isoformat()}
    
    def cleanup_invalid_tokens(self, tokens_to_remove: List[str]) -> bool:
        """
        Helper method to clean up invalid FCM tokens
        This could be expanded to integrate with User model
        """
        try:
            if not tokens_to_remove:
                return True
            
            # Log invalid tokens for manual cleanup or automated processing
            logger.info(f"Found {len(tokens_to_remove)} invalid FCM tokens for cleanup")
            
            # Here you could implement automatic token cleanup:
            # - Update User model to remove invalid tokens
            # - Queue tokens for batch cleanup
            # - Send to analytics for monitoring
            
            return True
            
        except Exception as e:
            logger.error(f"Error cleaning up invalid tokens: {e}")
            return False
