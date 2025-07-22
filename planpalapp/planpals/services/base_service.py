from abc import ABC, abstractmethod
from typing import Any, Dict, Optional
from django.conf import settings
import logging

logger = logging.getLogger(__name__)

class BaseService(ABC):
    """Base class cho tất cả services"""
    
    def __init__(self):
        self.logger = logger
    
    def log_error(self, message: str, exception: Exception = None):
        """Log error với context"""
        if exception:
            self.logger.error(f"{message}: {str(exception)}")
        else:
            self.logger.error(message)
    
    def log_info(self, message: str):
        """Log info"""
        self.logger.info(message)
    
    def log_debug(self, message: str):
        """Log debug"""
        self.logger.debug(message)
    
    @abstractmethod
    def validate_config(self) -> bool:
        """Kiểm tra cấu hình service"""
        pass
