"""
Groups Infrastructure — Domain Event Handler Registration
"""
from planpals.shared._event_registry import register_event_handler

from planpals.groups.domain.events import (
    GroupMemberAdded,
    GroupMemberRemoved,
    GroupRoleChanged,
)


def _handle_group_member_added(event: GroupMemberAdded):
    from planpals.shared.realtime_publisher import publish_group_member_added
    publish_group_member_added(
        group_id=event.group_id,
        user_id=event.user_id,
        username=event.username,
        role=event.role,
        group_name=event.group_name,
        added_by=event.added_by,
    )


def _handle_group_member_removed(event: GroupMemberRemoved):
    from planpals.shared.realtime_publisher import publish_group_member_removed
    publish_group_member_removed(
        group_id=event.group_id,
        user_id=event.user_id,
        username=event.username,
        group_name=event.group_name,
    )


def _handle_group_role_changed(event: GroupRoleChanged):
    from planpals.shared.realtime_publisher import publish_group_role_changed
    publish_group_role_changed(
        group_id=event.group_id,
        user_id=event.user_id,
        username=event.username,
        new_role=event.new_role,
        group_name=event.group_name,
    )


def register_group_event_handlers():
    """Register all group domain event handlers. Call from PlanPalsConfig.ready()."""
    register_event_handler(GroupMemberAdded, _handle_group_member_added)
    register_event_handler(GroupMemberRemoved, _handle_group_member_removed)
    register_event_handler(GroupRoleChanged, _handle_group_role_changed)
