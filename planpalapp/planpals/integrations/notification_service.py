from typing import Dict, List, Optional, Any, Tuple
from django.conf import settings
from django.core.cache import cache
from .base_service import BaseService
import logging
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, messaging
FIREBASE_ADMIN_AVAILABLE = True


logger = logging.getLogger(__name__)


class NotificationService(BaseService):
    """Firebase Cloud Messaging service using Admin SDK"""
    
    def __init__(self):
        super().__init__()
        self.batch_size = getattr(settings, 'FCM_BATCH_SIZE', 500)
        self.rate_limit_window = 3600  # 1 hour
        self.max_notifications_per_hour = getattr(settings, 'FCM_RATE_LIMIT', 1000)
        self.service_account_path = getattr(settings, 'FIREBASE_SERVICE_ACCOUNT_PATH', None)
        self.firebase_initialized = False
        
        # Initialize Firebase Admin SDK
        self._initialize_firebase()
    
    def _initialize_firebase(self) -> bool:
        """Initialize Firebase Admin SDK with service account"""
        if not FIREBASE_ADMIN_AVAILABLE:
            logger.error("firebase-admin package not installed. Run: pip install firebase-admin")
            return False
            
        if not self.service_account_path:
            logger.error("FIREBASE_SERVICE_ACCOUNT_PATH not configured in settings")
            return False
            
        try:
            sa_path = Path(self.service_account_path)
            if not sa_path.exists():
                logger.error(f"Service account file not found: {sa_path}")
                return False
                
            # Initialize Firebase app if not already done
            if not firebase_admin._apps:
                cred = credentials.Certificate(str(sa_path))
                firebase_admin.initialize_app(cred)
                logger.info("Firebase Admin SDK initialized successfully")
            
            self.firebase_initialized = True
            return True
            
        except Exception as e:
            logger.error(f"Failed to initialize Firebase Admin SDK: {e}")
            return False
    
    def validate_config(self) -> bool:
        return self.firebase_initialized and FIREBASE_ADMIN_AVAILABLE
    
    def check_rate_limit(self, user_id: str = None) -> bool:
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

        if not self.validate_config():
            logger.error("Firebase Admin SDK not properly configured")
            return 0, len(fcm_tokens)
        
        if not fcm_tokens:
            return 0, 0
        
        # Check global rate limit
        if not self.check_rate_limit():
            logger.warning("Global rate limit exceeded, skipping notifications")
            return 0, len(fcm_tokens)
        
        success_count = 0
        total_count = len(fcm_tokens)
        
        # Process tokens in batches
        for i in range(0, len(fcm_tokens), self.batch_size):
            batch_tokens = fcm_tokens[i:i + self.batch_size]
            
            try:
                if len(batch_tokens) > 1:
                    # Use multicast for multiple tokens
                    message = messaging.MulticastMessage(
                        tokens=batch_tokens,
                        notification=messaging.Notification(title=title, body=body),
                        data={k: str(v) for k, v in (data or {}).items()},
                        android=messaging.AndroidConfig(
                            priority='high',
                            ttl=3600,
                            notification=messaging.AndroidNotification(
                                sound='default',
                                default_sound=True
                            )
                        ),
                        apns=messaging.APNSConfig(
                            headers={'apns-priority': '10'},
                            payload=messaging.APNSPayload(
                                aps=messaging.Aps(sound='default')
                            )
                        ),
                    )
                    response = messaging.send_multicast(message)
                    batch_success = response.success_count
                    success_count += batch_success
                    
                    # Handle failures
                    if response.failure_count > 0:
                        self._handle_failed_responses(batch_tokens, response.responses)
                        
                else:
                    # Single token
                    message = messaging.Message(
                        token=batch_tokens[0],
                        notification=messaging.Notification(title=title, body=body),
                        data={k: str(v) for k, v in (data or {}).items()},
                        android=messaging.AndroidConfig(
                            priority='high',
                            ttl=3600,
                            notification=messaging.AndroidNotification(
                                sound='default',
                                default_sound=True
                            )
                        ),
                        apns=messaging.APNSConfig(
                            headers={'apns-priority': '10'},
                            payload=messaging.APNSPayload(
                                aps=messaging.Aps(sound='default')
                            )
                        ),
                    )
                    try:
                        messaging.send(message)
                        success_count += 1
                    except Exception as e:
                        self._handle_failed_token(batch_tokens[0], str(e))
                        
            except Exception as e:
                logger.error(f"FCM batch send failed for {len(batch_tokens)} tokens: {e}")
        
        logger.info(f"FCM batch send completed: {success_count}/{total_count} successful")
        return success_count, total_count
    
    def _handle_failed_responses(self, tokens: List[str], responses: List):
        """Handle failed responses from multicast"""
        for i, response in enumerate(responses):
            if not response.success and i < len(tokens):
                error_code = getattr(response.exception, 'code', str(response.exception))
                self._handle_failed_token(tokens[i], error_code)
    
    def _handle_failed_token(self, token: str, error: str):
        """Handle individual failed token"""
        if error in ['UNREGISTERED', 'INVALID_ARGUMENT']:
            # Token is invalid, should be removed from database
            logger.info(f"Invalid FCM token detected: {token[:10]}... (error: {error})")
            self._cleanup_invalid_token(token)
        else:
            logger.warning(f"FCM send failed for token {token[:10]}...: {error}")
    
    def _cleanup_invalid_token(self, token: str):
        """Remove invalid token from database"""
        try:
            from ..models import User
            User.objects.filter(fcm_token=token).update(fcm_token=None)
            logger.info(f"Cleaned up invalid FCM token: {token[:10]}...")
        except Exception as e:
            logger.error(f"Failed to cleanup invalid token: {e}")
    
    def send_push_notification(self, fcm_tokens: List[str], title: str, 
                             body: str, data: Optional[Dict[str, Any]] = None) -> bool:
        """Send push notification (backward compatibility method)"""
        success_count, total_count = self.send_push_notification_batch(fcm_tokens, title, body, data)
        return success_count > 0
    
    def send_group_notification(self, group_id: str, title: str, body: str, 
                              exclude_user_id: Optional[str] = None,
                              data: Optional[Dict[str, Any]] = None) -> bool:
        """Send notification to all group members"""
        from ..models import Group
        
        try:
            group = Group.objects.prefetch_related('members').get(id=group_id)
            members = group.members.exclude(fcm_token__isnull=True).exclude(fcm_token='')
            
            if exclude_user_id:
                members = members.exclude(id=exclude_user_id)
            
            fcm_tokens = list(members.values_list('fcm_token', flat=True))
            
            if not fcm_tokens:
                logger.info(f"No FCM tokens found for group {group_id}")
                return True
            
            # Add group info to data
            notification_data = data or {}
            notification_data.update({
                'group_id': group_id,
                'group_name': group.name
            })
            
            success_count, total_count = self.send_push_notification_batch(
                fcm_tokens, title, body, notification_data
            )
            
            logger.info(f"Group notification sent: {success_count}/{total_count} successful")
            return success_count > 0
            
        except Exception as e:
            logger.error(f"Failed to send group notification: {e}")
            return False
    
    def send_user_notification(self, user_id: str, title: str, body: str,
                             data: Optional[Dict[str, Any]] = None) -> bool:
        """Send notification to specific user"""
        from ..models import User
        
        try:
            user = User.objects.get(id=user_id)
            if not user.fcm_token:
                logger.info(f"User {user_id} has no FCM token")
                return True
            
            # Check individual rate limit
            if not self.check_rate_limit(user_id):
                logger.warning(f"Rate limit exceeded for user {user_id}")
                return False
            
            notification_data = data or {}
            notification_data.update({'user_id': user_id})
            
            success = self.send_push_notification([user.fcm_token], title, body, notification_data)
            logger.info(f"User notification sent to {user_id}: {success}")
            return success
            
        except Exception as e:
            logger.error(f"Failed to send user notification to {user_id}: {e}")
            return False