class CollaborationError(Exception):
    def __init__(self, message: str, code: str = 'collaboration_error'):
        super().__init__(message)
        self.message = message
        self.code = code


class CollaborationNotFound(CollaborationError):
    def __init__(self, message: str):
        super().__init__(message, 'not_found')


class CollaborationPermissionDenied(CollaborationError):
    def __init__(self, message: str):
        super().__init__(message, 'permission_denied')


class CollaborationConflict(CollaborationError):
    def __init__(self, message: str, code: str = 'conflict'):
        super().__init__(message, code)
