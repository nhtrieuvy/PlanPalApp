"""
Groups Application — Command Handlers

Each handler implements ONE use case for the groups bounded context.
"""
import logging
from typing import Any
from uuid import UUID

from django.db import transaction

from planpals.audit.domain.entities import AuditAction, AuditResourceType
from planpals.shared.interfaces import BaseCommandHandler, DomainEventPublisher
from planpals.groups.domain.repositories import GroupRepository, GroupMembershipRepository
from planpals.groups.domain.events import GroupMemberAdded, GroupMemberRemoved, GroupRoleChanged
from planpals.groups.application.commands import (
    CreateGroupCommand, UpdateGroupCommand, AddMemberCommand, RemoveMemberCommand,
    JoinGroupCommand, LeaveGroupCommand, DeleteGroupCommand,
    PromoteMemberCommand, DemoteMemberCommand,
)
from planpals.shared.domain_exceptions import (
    GroupNotFoundException, NotGroupAdminException, NotGroupMemberException,
    AlreadyGroupMemberException, LastAdminException,
    CannotRemoveAdminException, NotFriendsException,
)

logger = logging.getLogger(__name__)


class CreateGroupHandler(BaseCommandHandler[CreateGroupCommand, Any]):
    """
    Use case: Create a new group.
    Creates group, adds creator as admin, adds initial members,
    and creates associated group conversation.
    """

    def __init__(
        self,
        group_repo: GroupRepository,
        membership_repo: GroupMembershipRepository,
        event_publisher: DomainEventPublisher,
        friendship_checker=None,  # callable(user1_id, user2_id) -> bool
        conversation_creator=None,  # callable(group) -> conversation
    ):
        self.group_repo = group_repo
        self.membership_repo = membership_repo
        self.event_publisher = event_publisher
        self.friendship_checker = friendship_checker
        self.conversation_creator = conversation_creator

    @transaction.atomic
    def handle(self, command: CreateGroupCommand) -> Any:
        # Business rule: initial members must be friends with admin
        if self.friendship_checker and command.initial_member_ids:
            for member_id in command.initial_member_ids:
                if not self.friendship_checker(command.admin_id, member_id):
                    raise NotFriendsException()

        group = self.group_repo.save_new(command)

        # Add creator as admin
        self.membership_repo.add_member(group.id, command.admin_id, role='admin')

        # Add initial members
        for member_id in command.initial_member_ids:
            self.membership_repo.add_member(group.id, member_id, role='member')
            self.event_publisher.publish(GroupMemberAdded(
                group_id=str(group.id),
                user_id=str(member_id),
                username='',  # will be resolved by infrastructure
                role='member',
                group_name=group.name,
                added_by=str(command.admin_id),
            ))

        # Create group conversation
        if self.conversation_creator:
            self.conversation_creator(group)

        self._log(f"Group created: {group.id} by {command.admin_id}")
        return group


class UpdateGroupHandler(BaseCommandHandler[UpdateGroupCommand, Any]):
    """Use case: Update group details (name, description, media)."""

    def __init__(
        self,
        group_repo: GroupRepository,
        membership_repo: GroupMembershipRepository,
        event_publisher: DomainEventPublisher,
    ):
        self.group_repo = group_repo
        self.membership_repo = membership_repo
        self.event_publisher = event_publisher

    @transaction.atomic
    def handle(self, command: UpdateGroupCommand) -> Any:
        group = self.group_repo.get_by_id(command.group_id)
        if not group:
            raise GroupNotFoundException()

        # Business rule: only admins can update group details
        if not self.membership_repo.is_admin(command.group_id, command.user_id):
            raise NotGroupAdminException()

        update_fields = {}
        for field_name in ['name', 'description', 'avatar', 'cover_image']:
            value = getattr(command, field_name, None)
            if value is not None:
                update_fields[field_name] = value

        if update_fields:
            for k, v in update_fields.items():
                setattr(group, k, v)
            group = self.group_repo.save(group)

        self._log(f"Group updated: {group.id} by {command.user_id}")
        return group


class AddMemberHandler(BaseCommandHandler[AddMemberCommand, Any]):
    """Use case: Admin adds a member to the group."""

    def __init__(
        self,
        group_repo: GroupRepository,
        membership_repo: GroupMembershipRepository,
        event_publisher: DomainEventPublisher,
        friendship_checker=None,
    ):
        self.group_repo = group_repo
        self.membership_repo = membership_repo
        self.event_publisher = event_publisher
        self.friendship_checker = friendship_checker

    @transaction.atomic
    def handle(self, command: AddMemberCommand) -> Any:
        group = self.group_repo.get_by_id(command.group_id)
        if not group:
            raise GroupNotFoundException()

        # Business rule: only admins can add members
        if not self.membership_repo.is_admin(command.group_id, command.user_id):
            raise NotGroupAdminException()

        # Business rule: can't add existing members
        if self.membership_repo.is_member(command.group_id, command.target_user_id):
            raise AlreadyGroupMemberException()

        # Business rule: must be friends to add to group
        if self.friendship_checker and not self.friendship_checker(
            command.user_id, command.target_user_id
        ):
            raise NotFriendsException()

        membership = self.membership_repo.add_member(
            command.group_id, command.target_user_id, role='member'
        )

        self.event_publisher.publish(GroupMemberAdded(
            group_id=str(command.group_id),
            user_id=str(command.target_user_id),
            username='',
            role='member',
            group_name=group.name,
            added_by=str(command.user_id),
        ))

        return membership


class RemoveMemberHandler(BaseCommandHandler[RemoveMemberCommand, bool]):
    """Use case: Admin removes a member from the group."""

    def __init__(
        self,
        group_repo: GroupRepository,
        membership_repo: GroupMembershipRepository,
        event_publisher: DomainEventPublisher,
    ):
        self.group_repo = group_repo
        self.membership_repo = membership_repo
        self.event_publisher = event_publisher

    @transaction.atomic
    def handle(self, command: RemoveMemberCommand) -> bool:
        group = self.group_repo.get_by_id(command.group_id)
        if not group:
            raise GroupNotFoundException()

        if not self.membership_repo.is_admin(command.group_id, command.user_id):
            raise NotGroupAdminException()

        if not self.membership_repo.is_member(command.group_id, command.target_user_id):
            raise NotGroupMemberException()

        # Business rule: can't remove other admins
        if self.membership_repo.is_admin(command.group_id, command.target_user_id):
            raise CannotRemoveAdminException()

        self.membership_repo.remove_member(command.group_id, command.target_user_id)

        self.event_publisher.publish(GroupMemberRemoved(
            group_id=str(command.group_id),
            user_id=str(command.target_user_id),
            username='',
            group_name=group.name,
        ))

        return True


class JoinGroupHandler(BaseCommandHandler[JoinGroupCommand, Any]):
    """Use case: User joins a group by explicit group ID."""

    def __init__(
        self,
        group_repo: GroupRepository,
        membership_repo: GroupMembershipRepository,
        event_publisher: DomainEventPublisher,
        audit_service=None,
    ):
        self.group_repo = group_repo
        self.membership_repo = membership_repo
        self.event_publisher = event_publisher
        self.audit_service = audit_service

    @transaction.atomic
    def handle(self, command: JoinGroupCommand) -> Any:
        group = self.group_repo.get_by_id(command.group_id)
        if not group:
            raise GroupNotFoundException()

        if self.membership_repo.is_member(group.id, command.user_id):
            raise AlreadyGroupMemberException()

        membership = self.membership_repo.add_member(
            group.id, command.user_id, role='member'
        )

        self.event_publisher.publish(GroupMemberAdded(
            group_id=str(group.id),
            user_id=str(command.user_id),
            username='',
            role='member',
            group_name=group.name,
        ))

        if self.audit_service:
            self.audit_service.log_action(
                user=command.user_id,
                action=AuditAction.JOIN_GROUP.value,
                resource_type=AuditResourceType.GROUP.value,
                resource_id=group.id,
                metadata={
                    'group_name': group.name,
                    'role': 'member',
                },
            )

        return membership


class LeaveGroupHandler(BaseCommandHandler[LeaveGroupCommand, bool]):
    """Use case: Member leaves a group (with last-admin protection)."""

    def __init__(
        self,
        group_repo: GroupRepository,
        membership_repo: GroupMembershipRepository,
        event_publisher: DomainEventPublisher,
        audit_service=None,
    ):
        self.group_repo = group_repo
        self.membership_repo = membership_repo
        self.event_publisher = event_publisher
        self.audit_service = audit_service

    @transaction.atomic
    def handle(self, command: LeaveGroupCommand) -> bool:
        group = self.group_repo.get_by_id(command.group_id)
        if not group:
            raise GroupNotFoundException()

        if not self.membership_repo.is_member(command.group_id, command.user_id):
            raise NotGroupMemberException()

        # Business rule: last admin cannot leave
        role = self.membership_repo.get_role(command.group_id, command.user_id)
        if role == 'admin':
            admin_count = self.membership_repo.get_admin_count(command.group_id)
            if admin_count <= 1:
                raise LastAdminException()

        self.membership_repo.remove_member(command.group_id, command.user_id)

        self.event_publisher.publish(GroupMemberRemoved(
            group_id=str(command.group_id),
            user_id=str(command.user_id),
            username='',
        ))

        if self.audit_service:
            self.audit_service.log_action(
                user=command.user_id,
                action=AuditAction.LEAVE_GROUP.value,
                resource_type=AuditResourceType.GROUP.value,
                resource_id=command.group_id,
                metadata={
                    'group_name': group.name,
                    'role': role,
                },
            )

        return True


class PromoteMemberHandler(BaseCommandHandler[PromoteMemberCommand, bool]):

    def __init__(
        self,
        membership_repo: GroupMembershipRepository,
        event_publisher: DomainEventPublisher,
        audit_service=None,
    ):
        self.membership_repo = membership_repo
        self.event_publisher = event_publisher
        self.audit_service = audit_service

    @transaction.atomic
    def handle(self, command: PromoteMemberCommand) -> bool:
        if not self.membership_repo.is_admin(command.group_id, command.user_id):
            raise NotGroupAdminException()

        if not self.membership_repo.is_member(command.group_id, command.target_user_id):
            raise NotGroupMemberException()

        previous_role = self.membership_repo.get_role(command.group_id, command.target_user_id)
        self.membership_repo.set_role(command.group_id, command.target_user_id, 'admin')

        self.event_publisher.publish(GroupRoleChanged(
            group_id=str(command.group_id),
            user_id=str(command.target_user_id),
            username='',
            new_role='admin',
        ))

        if self.audit_service:
            self.audit_service.log_action(
                user=command.user_id,
                action=AuditAction.CHANGE_ROLE.value,
                resource_type=AuditResourceType.GROUP.value,
                resource_id=command.group_id,
                metadata={
                    'target_user_id': command.target_user_id,
                    'previous_role': previous_role,
                    'new_role': 'admin',
                },
            )

        return True


class DemoteMemberHandler(BaseCommandHandler[DemoteMemberCommand, bool]):

    def __init__(
        self,
        membership_repo: GroupMembershipRepository,
        event_publisher: DomainEventPublisher,
        audit_service=None,
    ):
        self.membership_repo = membership_repo
        self.event_publisher = event_publisher
        self.audit_service = audit_service

    @transaction.atomic
    def handle(self, command: DemoteMemberCommand) -> bool:
        if not self.membership_repo.is_admin(command.group_id, command.user_id):
            raise NotGroupAdminException()

        # Business rule: can't demote the last admin
        admin_count = self.membership_repo.get_admin_count(command.group_id)
        if admin_count <= 1 and self.membership_repo.is_admin(
            command.group_id, command.target_user_id
        ):
            raise LastAdminException()

        previous_role = self.membership_repo.get_role(command.group_id, command.target_user_id)
        self.membership_repo.set_role(command.group_id, command.target_user_id, 'member')

        self.event_publisher.publish(GroupRoleChanged(
            group_id=str(command.group_id),
            user_id=str(command.target_user_id),
            username='',
            new_role='member',
        ))

        if self.audit_service:
            self.audit_service.log_action(
                user=command.user_id,
                action=AuditAction.CHANGE_ROLE.value,
                resource_type=AuditResourceType.GROUP.value,
                resource_id=command.group_id,
                metadata={
                    'target_user_id': command.target_user_id,
                    'previous_role': previous_role,
                    'new_role': 'member',
                },
            )

        return True


class DeleteGroupHandler(BaseCommandHandler[DeleteGroupCommand, bool]):

    def __init__(
        self,
        group_repo: GroupRepository,
        membership_repo: GroupMembershipRepository,
        audit_service=None,
    ):
        self.group_repo = group_repo
        self.membership_repo = membership_repo
        self.audit_service = audit_service

    @transaction.atomic
    def handle(self, command: DeleteGroupCommand) -> bool:
        group = self.group_repo.get_by_id(command.group_id)
        if not group:
            raise GroupNotFoundException()

        if str(group.admin_id) != str(command.user_id):
            raise NotGroupAdminException()

        deletion_metadata = {
            'group_name': group.name,
            'admin_id': group.admin_id,
            'member_count': group.member_count,
            'plans_count': group.plans_count,
            'member_ids': list(group.members.values_list('id', flat=True)),
        }
        deleted = self.group_repo.delete(command.group_id)

        if deleted and self.audit_service:
            self.audit_service.log_action(
                user=command.user_id,
                action=AuditAction.DELETE_GROUP.value,
                resource_type=AuditResourceType.GROUP.value,
                resource_id=command.group_id,
                metadata=deletion_metadata,
            )

        return deleted
