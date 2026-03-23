"""
Pure Python Domain Exceptions — NO Django / DRF imports.

These are the CANONICAL exception types for the domain and application layers.
They carry an error code and HTTP-like status hint so the API layer can map
them to proper HTTP responses without the domain knowing about DRF.

Hierarchy:
    DomainException (base)
    ├── ValidationException      (400)
    ├── NotFoundException        (404)
    ├── PermissionException      (403)
    └── ConflictException        (409)
    └── RateLimitException       (429)

The API-layer exception mapper (exception_handler.py) converts these into
DRF Response objects.
"""


class DomainException(Exception):
    """Base exception for all domain / application errors."""
    status_hint: int = 400
    default_code: str = 'error'
    default_detail: str = 'Đã xảy ra lỗi.'

    def __init__(self, detail: str | None = None, code: str | None = None):
        self.detail = detail or self.default_detail
        self.code = code or self.default_code
        super().__init__(self.detail)


# ---------------------------------------------------------------------------
# Category base classes
# ---------------------------------------------------------------------------

class ValidationException(DomainException):
    """Business-rule validation failed (HTTP 400)."""
    status_hint = 400
    default_code = 'validation_error'


class NotFoundException(DomainException):
    """Entity not found (HTTP 404)."""
    status_hint = 404
    default_code = 'not_found'


class PermissionException(DomainException):
    """Caller lacks permission (HTTP 403)."""
    status_hint = 403
    default_code = 'permission_denied'


class ConflictException(DomainException):
    """Action conflicts with current state (HTTP 409)."""
    status_hint = 409
    default_code = 'conflict'


class RateLimitException(DomainException):
    """Too many requests / cooldown active (HTTP 429)."""
    status_hint = 429
    default_code = 'rate_limited'


# ---------------------------------------------------------------------------
# Concrete domain exceptions — Plans
# ---------------------------------------------------------------------------

class PlanCompletedException(ValidationException):
    default_detail = 'Không thể thực hiện thao tác này vì kế hoạch đã hoàn thành.'
    default_code = 'plan_completed'


class PlanCancelledException(ValidationException):
    default_detail = 'Không thể thực hiện thao tác này vì kế hoạch đã bị hủy.'
    default_code = 'plan_cancelled'


class ActivityOverlapException(ValidationException):
    default_detail = 'Hoạt động này trùng thời gian với hoạt động khác trong kế hoạch.'
    default_code = 'activity_overlap'


class NotPlanOwnerException(PermissionException):
    default_detail = 'Bạn không có quyền chỉnh sửa kế hoạch này. Chỉ người tạo mới có thể thực hiện.'
    default_code = 'not_plan_owner'


class PlanNotFoundException(NotFoundException):
    default_detail = 'Không tìm thấy kế hoạch.'
    default_code = 'plan_not_found'


class ActivityNotFoundException(NotFoundException):
    default_detail = 'Không tìm thấy hoạt động.'
    default_code = 'activity_not_found'


class InvalidDateRangeException(ValidationException):
    default_detail = 'Ngày kết thúc phải sau ngày bắt đầu.'
    default_code = 'invalid_date_range'


class ActivityOutsidePlanDateException(ValidationException):
    default_detail = 'Hoạt động phải nằm trong khoảng thời gian của kế hoạch.'
    default_code = 'activity_outside_plan_date'


class ActivityEndAfterPlanException(ValidationException):
    default_detail = 'Thời gian kết thúc hoạt động không được vượt quá ngày kết thúc của kế hoạch.'
    default_code = 'activity_end_after_plan'


class ActivityStartBeforePlanException(ValidationException):
    default_detail = 'Thời gian bắt đầu hoạt động không được sớm hơn ngày bắt đầu của kế hoạch.'
    default_code = 'activity_start_before_plan'


class ActivityDurationExceededException(ValidationException):
    default_detail = 'Thời lượng hoạt động không được vượt quá 24 giờ.'
    default_code = 'activity_duration_exceeded'


class InvalidTimeRangeException(ValidationException):
    default_detail = 'Thời gian kết thúc phải sau thời gian bắt đầu.'
    default_code = 'invalid_time_range'


class InvalidStatusTransitionException(ValidationException):
    default_code = 'invalid_status_transition'
    default_detail = 'Không thể chuyển trạng thái.'


# ---------------------------------------------------------------------------
# Concrete domain exceptions — Groups
# ---------------------------------------------------------------------------

class NotGroupAdminException(PermissionException):
    default_detail = 'Bạn không có quyền quản trị nhóm này. Chỉ quản trị viên mới có thể thực hiện.'
    default_code = 'not_group_admin'


class NotGroupMemberException(PermissionException):
    default_detail = 'Bạn không phải là thành viên của nhóm này.'
    default_code = 'not_group_member'


class AlreadyGroupMemberException(ValidationException):
    default_detail = 'Bạn đã là thành viên của nhóm này rồi.'
    default_code = 'already_member'


class LastAdminException(ValidationException):
    default_detail = 'Không thể rời nhóm vì bạn là quản trị viên duy nhất. Hãy chỉ định quản trị viên mới trước.'
    default_code = 'last_admin'


class CannotRemoveAdminException(PermissionException):
    default_detail = 'Không thể xóa quản trị viên khác khỏi nhóm.'
    default_code = 'cannot_remove_admin'


class GroupNotFoundException(NotFoundException):
    default_detail = 'Không tìm thấy nhóm.'
    default_code = 'group_not_found'


class MaxMembersExceededException(ValidationException):
    default_detail = 'Nhóm đã đạt số lượng thành viên tối đa.'
    default_code = 'max_members_exceeded'


class NotFriendsException(ValidationException):
    default_detail = 'Chỉ có thể thêm bạn bè vào nhóm.'
    default_code = 'not_friends'


# ---------------------------------------------------------------------------
# Concrete domain exceptions — Auth / Users
# ---------------------------------------------------------------------------

class UserNotFoundException(NotFoundException):
    default_detail = 'Không tìm thấy người dùng.'
    default_code = 'user_not_found'


class AlreadyFriendsException(ValidationException):
    default_detail = 'Bạn đã là bạn bè với người dùng này rồi.'
    default_code = 'already_friends'


class FriendRequestAlreadySentException(ValidationException):
    default_detail = 'Lời mời kết bạn đã được gửi trước đó.'
    default_code = 'request_already_sent'


class UserBlockedException(PermissionException):
    default_detail = 'Không thể thực hiện thao tác này vì bạn đã chặn hoặc bị chặn bởi người dùng này.'
    default_code = 'user_blocked'


class CannotSendToSelfException(ValidationException):
    default_detail = 'Không thể gửi lời mời kết bạn cho chính mình.'
    default_code = 'cannot_send_to_self'


class FriendRequestNotFoundException(NotFoundException):
    default_detail = 'Không tìm thấy lời mời kết bạn.'
    default_code = 'friend_request_not_found'


class RejectionCooldownException(RateLimitException):
    default_code = 'rejection_cooldown'

    def __init__(self, detail: str | None = None, remaining_time: str | None = None):
        if detail is None and remaining_time:
            detail = f'Không thể gửi lại lời mời kết bạn. Vui lòng đợi thêm {remaining_time}.'
        super().__init__(detail)


# ---------------------------------------------------------------------------
# Concrete domain exceptions — Chat
# ---------------------------------------------------------------------------

class ConversationNotFoundException(NotFoundException):
    default_detail = 'Không tìm thấy cuộc trò chuyện.'
    default_code = 'conversation_not_found'


class NotConversationParticipantException(PermissionException):
    default_detail = 'Bạn không phải là thành viên của cuộc trò chuyện này.'
    default_code = 'not_conversation_participant'


class MessageEditTimeExpiredException(PermissionException):
    default_detail = 'Không thể chỉnh sửa tin nhắn sau 15 phút.'
    default_code = 'message_edit_time_expired'


class NotMessageOwnerException(PermissionException):
    default_detail = 'Bạn không có quyền chỉnh sửa tin nhắn này.'
    default_code = 'not_message_owner'


# ---------------------------------------------------------------------------
# Concrete domain exceptions — Files
# ---------------------------------------------------------------------------

class InvalidFileTypeException(ValidationException):
    default_detail = 'Định dạng file không được hỗ trợ.'
    default_code = 'invalid_file_type'


class FileSizeTooLargeException(ValidationException):
    default_detail = 'Kích thước file quá lớn. Kích thước tối đa là 10MB.'
    default_code = 'file_size_too_large'
