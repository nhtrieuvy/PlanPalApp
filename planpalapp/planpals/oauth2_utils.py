# ============================================================================
# PLANPAL OAUTH2 UTILITIES - Token Management Helpers
# ============================================================================

from django.utils import timezone
from oauth2_provider.models import Application, AccessToken
from oauth2_provider import settings as oauth2_settings
from django.contrib.auth import get_user_model
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
    def revoke_user_tokens(user):
        """Revoke all tokens for a user (logout from all devices)"""
        if not user:
            return False
        
        try:
            # Delete all access tokens
            access_tokens_count = AccessToken.objects.filter(user=user).count()
            AccessToken.objects.filter(user=user).delete()
            
            logger.info(f"Revoked {access_tokens_count} access tokens for user: {user.username}")
            return True
            
        except Exception as e:
            logger.error(f"Error revoking tokens for user {user.username}: {str(e)}")
            return False
    
    @staticmethod
    def cleanup_expired_tokens():
        """Clean up expired access tokens (Refresh tokens managed by DOT)."""
        now = timezone.now()
        
        # Delete expired access tokens
        expired_access_tokens = AccessToken.objects.filter(expires__lt=now).count()
        AccessToken.objects.filter(expires__lt=now).delete()
        logger.info(f"Cleaned up {expired_access_tokens} expired access tokens")
        return {'expired_access_tokens': expired_access_tokens}


class OAuth2ResponseFormatter:
    """
    Utility for formatting OAuth2 responses consistently
    """
    
    @staticmethod
    def success_response(access_token, refresh_token=None, user_data=None):
        """Format successful token response (used only by legacy custom login)."""
        expires_in = getattr(oauth2_settings, 'ACCESS_TOKEN_EXPIRE_SECONDS', 3600)
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
