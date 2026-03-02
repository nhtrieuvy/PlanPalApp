from typing import Dict, Any
import logging

logger = logging.getLogger(__name__)


class BaseService:
    @staticmethod
    def log_operation(operation: str, details: Dict[str, Any] = None):
        logger.info(f"Service operation: {operation}", extra=details or {})
    
    @staticmethod
    def log_error(message: str, error: Exception, details: Dict[str, Any] = None):
        logger.error(f"{message}: {str(error)}", extra=details or {}, exc_info=True)
    
    @staticmethod
    def validate_user_permission(user, resource, permission_type: str) -> bool:
        if not user or not user.is_authenticated:
            return False
        return True
