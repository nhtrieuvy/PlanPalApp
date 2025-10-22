"""
Custom exceptions for PlanPal application with user-friendly messages
"""
from rest_framework.exceptions import APIException
from rest_framework import status


class PlanPalException(APIException):
    """Base exception for PlanPal application"""
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Đã xảy ra lỗi.'
    default_code = 'error'


class PlanCompletedException(PlanPalException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Không thể thực hiện thao tác này vì kế hoạch đã hoàn thành.'
    default_code = 'plan_completed'


class PlanCancelledException(PlanPalException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Không thể thực hiện thao tác này vì kế hoạch đã bị hủy.'
    default_code = 'plan_cancelled'


class ActivityOverlapException(PlanPalException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Hoạt động này trùng thời gian với hoạt động khác trong kế hoạch.'
    default_code = 'activity_overlap'


class NotPlanOwnerException(PlanPalException):
    status_code = status.HTTP_403_FORBIDDEN
    default_detail = 'Bạn không có quyền chỉnh sửa kế hoạch này. Chỉ người tạo mới có thể thực hiện.'
    default_code = 'not_plan_owner'


class NotGroupAdminException(PlanPalException):
    status_code = status.HTTP_403_FORBIDDEN
    default_detail = 'Bạn không có quyền quản trị nhóm này. Chỉ quản trị viên mới có thể thực hiện.'
    default_code = 'not_group_admin'


class NotGroupMemberException(PlanPalException):
    status_code = status.HTTP_403_FORBIDDEN
    default_detail = 'Bạn không phải là thành viên của nhóm này.'
    default_code = 'not_group_member'


class AlreadyGroupMemberException(PlanPalException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Bạn đã là thành viên của nhóm này rồi.'
    default_code = 'already_member'


class LastAdminException(PlanPalException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Không thể rời nhóm vì bạn là quản trị viên duy nhất. Hãy chỉ định quản trị viên mới trước.'
    default_code = 'last_admin'


class CannotRemoveAdminException(PlanPalException):
    status_code = status.HTTP_403_FORBIDDEN
    default_detail = 'Không thể xóa quản trị viên khác khỏi nhóm.'
    default_code = 'cannot_remove_admin'


class UserNotFoundException(PlanPalException):
    status_code = status.HTTP_404_NOT_FOUND
    default_detail = 'Không tìm thấy người dùng.'
    default_code = 'user_not_found'


class GroupNotFoundException(PlanPalException):
    status_code = status.HTTP_404_NOT_FOUND
    default_detail = 'Không tìm thấy nhóm.'
    default_code = 'group_not_found'


class PlanNotFoundException(PlanPalException):
    status_code = status.HTTP_404_NOT_FOUND
    default_detail = 'Không tìm thấy kế hoạch.'
    default_code = 'plan_not_found'


class ActivityNotFoundException(PlanPalException):
    status_code = status.HTTP_404_NOT_FOUND
    default_detail = 'Không tìm thấy hoạt động.'
    default_code = 'activity_not_found'


class ConversationNotFoundException(PlanPalException):
    status_code = status.HTTP_404_NOT_FOUND
    default_detail = 'Không tìm thấy cuộc trò chuyện.'
    default_code = 'conversation_not_found'


class AlreadyFriendsException(PlanPalException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Bạn đã là bạn bè với người dùng này rồi.'
    default_code = 'already_friends'


class FriendRequestAlreadySentException(PlanPalException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Lời mời kết bạn đã được gửi trước đó.'
    default_code = 'request_already_sent'


class UserBlockedException(PlanPalException):
    status_code = status.HTTP_403_FORBIDDEN
    default_detail = 'Không thể thực hiện thao tác này vì bạn đã chặn hoặc bị chặn bởi người dùng này.'
    default_code = 'user_blocked'


class CannotSendToSelfException(PlanPalException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Không thể gửi lời mời kết bạn cho chính mình.'
    default_code = 'cannot_send_to_self'


class FriendRequestNotFoundException(PlanPalException):
    status_code = status.HTTP_404_NOT_FOUND
    default_detail = 'Không tìm thấy lời mời kết bạn.'
    default_code = 'friend_request_not_found'


class InvalidDateRangeException(PlanPalException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Ngày kết thúc phải sau ngày bắt đầu.'
    default_code = 'invalid_date_range'


class ActivityOutsidePlanDateException(PlanPalException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Hoạt động phải nằm trong khoảng thời gian của kế hoạch.'
    default_code = 'activity_outside_plan_date'


class ActivityEndAfterPlanException(PlanPalException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Thời gian kết thúc hoạt động không được vượt quá ngày kết thúc của kế hoạch.'
    default_code = 'activity_end_after_plan'


class ActivityStartBeforePlanException(PlanPalException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Thời gian bắt đầu hoạt động không được sớm hơn ngày bắt đầu của kế hoạch.'
    default_code = 'activity_start_before_plan'


class ActivityDurationExceededException(PlanPalException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Thời lượng hoạt động không được vượt quá 24 giờ.'
    default_code = 'activity_duration_exceeded'


class InvalidTimeRangeException(PlanPalException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Thời gian kết thúc phải sau thời gian bắt đầu.'
    default_code = 'invalid_time_range'


class NotConversationParticipantException(PlanPalException):
    status_code = status.HTTP_403_FORBIDDEN
    default_detail = 'Bạn không phải là thành viên của cuộc trò chuyện này.'
    default_code = 'not_conversation_participant'


class MessageEditTimeExpiredException(PlanPalException):
    status_code = status.HTTP_403_FORBIDDEN
    default_detail = 'Không thể chỉnh sửa tin nhắn sau 15 phút.'
    default_code = 'message_edit_time_expired'


class NotMessageOwnerException(PlanPalException):
    status_code = status.HTTP_403_FORBIDDEN
    default_detail = 'Bạn không có quyền chỉnh sửa tin nhắn này.'
    default_code = 'not_message_owner'


class MaxMembersExceededException(PlanPalException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Nhóm đã đạt số lượng thành viên tối đa.'
    default_code = 'max_members_exceeded'


class InviteCodeInvalidException(PlanPalException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Mã mời không hợp lệ hoặc đã hết hạn.'
    default_code = 'invalid_invite_code'


class NotFriendsException(PlanPalException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Chỉ có thể thêm bạn bè vào nhóm.'
    default_code = 'not_friends'


class RejectionCooldownException(PlanPalException):
    status_code = status.HTTP_429_TOO_MANY_REQUESTS
    default_code = 'rejection_cooldown'
    
    def __init__(self, detail=None, remaining_time=None):
        if detail is None:
            detail = f'Không thể gửi lại lời mời kết bạn. Vui lòng đợi thêm {remaining_time}.'
        super().__init__(detail)


class InvalidFileTypeException(PlanPalException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Định dạng file không được hỗ trợ.'
    default_code = 'invalid_file_type'


class FileSizeTooLargeException(PlanPalException):
    status_code = status.HTTP_400_BAD_REQUEST
    default_detail = 'Kích thước file quá lớn. Kích thước tối đa là 10MB.'
    default_code = 'file_size_too_large'
