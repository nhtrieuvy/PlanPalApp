# ============================================================================
# PLANPAL OAUTH2 UTILITIES - Token Management Helpers
# ============================================================================

from django.utils import timezone
from oauth2_provider.models import Application, AccessToken, RefreshToken
from oauth2_provider import settings as oauth2_settings
from django.contrib.auth import get_user_model
import uuid
import logging

logger = logging.getLogger(__name__)
User = get_user_model()


class OAuth2TokenManager:
    """
    Centralized OAuth2 token management utility
    """
    
    @staticmethod
    def get_or_create_application():
        """Get or create OAuth2 application"""
        app, _ = Application.objects.get_or_create(
            name="PlanPalApp",
            defaults={
                'client_type': Application.CLIENT_CONFIDENTIAL,
                'authorization_grant_type': Application.GRANT_PASSWORD,
            }
        )
        
        return app
    
    @staticmethod
    def create_tokens_for_user(user):
        """Create both access and refresh tokens for user"""
        if not user or not user.is_active:
            raise ValueError("User must be active to create tokens")
        
        app = OAuth2TokenManager.get_or_create_application()
        
        # Get access/refresh token expiry (timedelta)
        access_token_expire = getattr(oauth2_settings, 'ACCESS_TOKEN_EXPIRE', timezone.timedelta(hours=1))
        

        # Create access token
        access_token = AccessToken.objects.create(
            user=user,
            application=app,
            token=uuid.uuid4().hex,
            expires=timezone.now() + access_token_expire,
            scope='read write'
        )

        # Create refresh token
        refresh_token = RefreshToken.objects.create(
            user=user,
            token=uuid.uuid4().hex,
            access_token=access_token,
            application=app,
        )
        
        logger.info(f"Created tokens for user: {user.username}")
        return access_token.token, refresh_token.token
    

    @staticmethod
    def revoke_user_tokens(user):
        """Revoke all tokens for a user (logout from all devices)"""
        if not user:
            return False
        
        try:
            # Delete all access tokens
            access_tokens_count = AccessToken.objects.filter(user=user).count()
            AccessToken.objects.filter(user=user).delete()
            
            # Delete all refresh tokens
            refresh_tokens_count = RefreshToken.objects.filter(user=user).count()
            RefreshToken.objects.filter(user=user).delete()
            
            logger.info(f"Revoked {access_tokens_count} access tokens and {refresh_tokens_count} refresh tokens for user: {user.username}")
            return True
            
        except Exception as e:
            logger.error(f"Error revoking tokens for user {user.username}: {str(e)}")
            return False
    
    @staticmethod
    def cleanup_expired_tokens():
        """Clean up expired tokens (can be run as a scheduled task)"""
        now = timezone.now()
        
        # Delete expired access tokens
        expired_access_tokens = AccessToken.objects.filter(expires__lt=now).count()
        AccessToken.objects.filter(expires__lt=now).delete()
        
        # Delete expired refresh tokens
        expired_refresh_tokens = RefreshToken.objects.filter(expires__lt=now).count()
        RefreshToken.objects.filter(expires__lt=now).delete()
        
        logger.info(f"Cleaned up {expired_access_tokens} expired access tokens and {expired_refresh_tokens} expired refresh tokens")
        
        return {
            'expired_access_tokens': expired_access_tokens,
            'expired_refresh_tokens': expired_refresh_tokens
        }


class OAuth2ResponseFormatter:
    """
    Utility for formatting OAuth2 responses consistently
    """
    
    @staticmethod
    def success_response(access_token, refresh_token=None, user_data=None):
        """Format successful token response"""
        # Get expires_in as seconds (int)
        access_token_expire = getattr(oauth2_settings, 'ACCESS_TOKEN_EXPIRE', timezone.timedelta(hours=1))
        expires_in = int(getattr(access_token_expire, 'total_seconds', lambda: 3600)())
        response = {
            'access_token': access_token,
            'token_type': 'Bearer',
            'expires_in': expires_in,
            'scope': 'read write',
        }
        
        if refresh_token:
            response['refresh_token'] = refresh_token
        
        if user_data:
            response['user'] = user_data
        
        return response
    
    @staticmethod
    def error_response(error_code, description, status_code=400):
        """Format error response according to OAuth2 spec"""
        return {
            'error': error_code,
            'error_description': description,
            'timestamp': timezone.now().isoformat()
        }, status_code
    
    @staticmethod
    def token_expired_response():
        """Standard response for expired tokens"""
        return OAuth2ResponseFormatter.error_response(
            'invalid_token',
            'The access token is expired',
            401
        )
    
    @staticmethod
    def invalid_token_response():
        """Standard response for invalid tokens"""
        return OAuth2ResponseFormatter.error_response(
            'invalid_token', 
            'The access token is invalid',
            401
        )
    
    @staticmethod
    def invalid_refresh_token_response():
        """Standard response for invalid refresh tokens"""
        return OAuth2ResponseFormatter.error_response(
            'invalid_grant',
            'The refresh token is invalid or expired',
            401
        )
