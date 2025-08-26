from typing import Dict, List, Optional, Any
from django.conf import settings
from django.core.mail import send_mail
from django.template.loader import render_to_string
from .base_service import BaseService
import json
import requests

class NotificationService(BaseService):
    """Service để gửi thông báo push notification và email"""
    
    def __init__(self):
        super().__init__()
        self.fcm_server_key = getattr(settings, 'FCM_SERVER_KEY', None)
        self.fcm_url = "https://fcm.googleapis.com/fcm/send"
    
    def validate_config(self) -> bool:
        """Kiểm tra cấu hình notification"""
        if not self.fcm_server_key:
            self.log_error("FCM Server Key không được cấu hình")
            return False
        return True
    
    def send_push_notification(self, fcm_tokens: List[str], title: str, 
                             body: str, data: Optional[Dict[str, Any]] = None) -> bool:
        """
        Gửi push notification đến nhiều device
        
        Args:
            fcm_tokens: Danh sách FCM tokens
            title: Tiêu đề thông báo
            body: Nội dung thông báo
            data: Dữ liệu bổ sung
        """
        if not self.validate_config():
            return False
        
        if not fcm_tokens:
            self.log_error("Danh sách FCM tokens trống")
            return False
        
        headers = {
            'Authorization': f'key={self.fcm_server_key}',
            'Content-Type': 'application/json',
        }
        
        # Gửi từng token một để tracking tốt hơn
        success_count = 0
        for token in fcm_tokens:
            payload = {
                'to': token,
                'notification': {
                    'title': title,
                    'body': body,
                    'sound': 'default'
                },
                'priority': 'high'
            }
            
            if data:
                payload['data'] = data
            
            try:
                response = requests.post(
                    self.fcm_url,
                    headers=headers,
                    data=json.dumps(payload)
                )
                
                if response.status_code == 200:
                    result = response.json()
                    if result.get('success', 0) > 0:
                        success_count += 1
                    else:
                        self.log_error(f"FCM error cho token {token[:10]}...: {result}")
                else:
                    self.log_error(f"HTTP error {response.status_code} cho token {token[:10]}...")
                    
            except Exception as e:
                self.log_error(f"Lỗi khi gửi notification cho token {token[:10]}...", e)
        
        self.log_info(f"Gửi thành công {success_count}/{len(fcm_tokens)} notifications")
        return success_count > 0
    
    def send_group_notification(self, group_id: str, title: str, body: str, 
                              exclude_user_id: Optional[str] = None,
                              data: Optional[Dict[str, Any]] = None) -> bool:
        """
        Gửi thông báo cho tất cả thành viên trong group
        
        Args:
            group_id: ID của group
            title: Tiêu đề thông báo
            body: Nội dung thông báo
            exclude_user_id: ID user không gửi thông báo (thường là người gửi)
            data: Dữ liệu bổ sung
        """
        from ..models import Group  # Import ở đây để tránh circular import
        
        try:
            group = Group.objects.get(id=group_id)
            members = group.members.all()
            
            if exclude_user_id:
                members = members.exclude(id=exclude_user_id)
            
            # Lấy FCM tokens của các thành viên
            fcm_tokens = []
            for member in members:
                if hasattr(member, 'fcm_token') and member.fcm_token:
                    fcm_tokens.append(member.fcm_token)
            
            if not fcm_tokens:
                self.log_info(f"Không có FCM token nào cho group {group_id}")
                return False
            
            # Thêm thông tin group vào data
            notification_data = {
                'type': 'group_notification',
                'group_id': group_id,
                'group_name': group.name
            }
            if data:
                notification_data.update(data)
            
            return self.send_push_notification(fcm_tokens, title, body, notification_data)
            
        except Group.DoesNotExist:
            self.log_error(f"Group {group_id} không tồn tại")
            return False
        except Exception as e:
            self.log_error(f"Lỗi khi gửi group notification", e)
            return False
    
    def send_plan_notification(self, plan_id: str, title: str, body: str,
                             exclude_user_id: Optional[str] = None,
                             data: Optional[Dict[str, Any]] = None) -> bool:
        """
        Gửi thông báo cho tất cả thành viên trong plan
        
        Args:
            plan_id: ID của plan
            title: Tiêu đề thông báo
            body: Nội dung thông báo
            exclude_user_id: ID user không gửi thông báo
            data: Dữ liệu bổ sung
        """
        from ..models import Plan  # Import ở đây để tránh circular import
        
        try:
            plan = Plan.objects.get(id=plan_id)
            # sử dụng helper để tránh lỗi thuộc tính không tồn tại
            members = plan.get_members()
            
            if exclude_user_id:
                members = members.exclude(id=exclude_user_id)
            
            # Lấy FCM tokens của các thành viên
            fcm_tokens = []
            for member in members:
                if hasattr(member, 'fcm_token') and member.fcm_token:
                    fcm_tokens.append(member.fcm_token)
            
            if not fcm_tokens:
                self.log_info(f"Không có FCM token nào cho plan {plan_id}")
                return False
            
            # Thêm thông tin plan vào data
            notification_data = {
                'type': 'plan_notification',
                'plan_id': plan_id,
                'plan_title': plan.title
            }
            if data:
                notification_data.update(data)
            
            return self.send_push_notification(fcm_tokens, title, body, notification_data)
            
        except Plan.DoesNotExist:
            self.log_error(f"Plan {plan_id} không tồn tại")
            return False
        except Exception as e:
            self.log_error(f"Lỗi khi gửi plan notification", e)
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
        elif update_type == 'plan_updated':
            body = f"{updater_name} đã cập nhật thông tin kế hoạch"
        else:
            body = f"{updater_name} đã cập nhật kế hoạch"
        
        data = {
            'action': 'plan_updated',
            'updater_id': updater_id,
            'update_type': update_type
        }
        
        return self.send_plan_notification(plan_id, title, body, updater_id, data)
    
    def notify_invitation(self, user_id: str, inviter_name: str, 
                        invitation_type: str, item_name: str) -> bool:
        """Thông báo lời mời tham gia group/plan"""
        from ..models import User  # Import ở đây để tránh circular import
        
        try:
            user = User.objects.get(id=user_id)
            if not hasattr(user, 'fcm_token') or not user.fcm_token:
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
            
            return self.send_push_notification([user.fcm_token], title, body, data)
            
        except User.DoesNotExist:
            self.log_error(f"User {user_id} không tồn tại")
            return False
        except Exception as e:
            self.log_error(f"Lỗi khi gửi invitation notification", e)
            return False

    def notify_friend_request(self, user_id: str, requester_name: str) -> bool:
        """Thông báo lời mời kết bạn"""
        from ..models import User  # Import ở đây để tránh circular import
        
        try:
            user = User.objects.get(id=user_id)
            if not hasattr(user, 'fcm_token') or not user.fcm_token:
                return False
            
            title = "Lời mời kết bạn"
            body = f"{requester_name} đã gửi lời mời kết bạn"
            
            data = {
                'action': 'friend_request',
                'requester_name': requester_name,
                'type': 'friend_request'
            }
            
            return self.send_push_notification([user.fcm_token], title, body, data)
            
        except User.DoesNotExist:
            self.log_error(f"User {user_id} không tồn tại")
            return False
        except Exception as e:
            self.log_error(f"Lỗi khi gửi friend request notification", e)
            return False

    def notify_friend_request_accepted(self, user_id: str, accepter_name: str) -> bool:
        """Thông báo lời mời kết bạn được chấp nhận"""
        from ..models import User  # Import ở đây để tránh circular import
        
        try:
            user = User.objects.get(id=user_id)
            if not hasattr(user, 'fcm_token') or not user.fcm_token:
                return False
            
            title = "Kết bạn thành công"
            body = f"{accepter_name} đã chấp nhận lời mời kết bạn của bạn"
            
            data = {
                'action': 'friend_request_accepted',
                'accepter_name': accepter_name,
                'type': 'friend_request_accepted'
            }
            
            return self.send_push_notification([user.fcm_token], title, body, data)
            
        except User.DoesNotExist:
            self.log_error(f"User {user_id} không tồn tại")
            return False
        except Exception as e:
            self.log_error(f"Lỗi khi gửi friend request accepted notification", e)
            return False
