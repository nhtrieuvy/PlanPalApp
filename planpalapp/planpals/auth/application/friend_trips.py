import logging

from django.db import transaction
from django.db.models import Q
from rest_framework.exceptions import NotFound, PermissionDenied, ValidationError

from planpals.auth.infrastructure.models import FriendTripInvitation, Friendship
from planpals.groups.application.services import GroupService

logger = logging.getLogger(__name__)


def _notify_recipient(user_id, actor, invitation, event):
    try:
        from planpals.notifications.application.factories import get_notification_service
        from planpals.notifications.domain.entities import NotificationType

        get_notification_service().notify(
            user_id,
            NotificationType.FRIEND_TRIP_INVITE.value,
            {
                'actor_name': actor.get_full_name() or actor.username,
                'group_name': invitation.name,
                'invitation_id': str(invitation.id),
                'event': event,
            },
        )
    except Exception:
        logger.exception('Unable to deliver trip invitation notification %s', invitation.id)


def invitation_payload(invitation):
    return {
        'id': str(invitation.id),
        'name': invitation.name,
        'status': invitation.status,
        'sender': {
            'id': str(invitation.sender_id),
            'name': invitation.sender.get_full_name() or invitation.sender.username,
        },
        'recipient': {
            'id': str(invitation.recipient_id),
            'name': invitation.recipient.get_full_name() or invitation.recipient.username,
        },
        'group_id': str(invitation.group_id) if invitation.group_id else None,
        'created_at': invitation.created_at.isoformat(),
    }


def cancel_pending_between(user_a, user_b):
    FriendTripInvitation.objects.filter(
        Q(sender=user_a, recipient=user_b) |
        Q(sender=user_b, recipient=user_a),
        status=FriendTripInvitation.PENDING,
    ).update(status=FriendTripInvitation.CANCELLED, pending_key=None)


@transaction.atomic
def send_invitation(sender, recipient, name):
    friendship = Friendship.objects.between_users(sender, recipient).select_for_update().first()
    if not friendship or friendship.status != Friendship.ACCEPTED:
        raise PermissionDenied('Only accepted friends can plan together.')
    if FriendTripInvitation.objects.filter(pending_key=friendship.id).exists():
        raise ValidationError({'friend': 'A trip invitation is already pending.'})
    invitation = FriendTripInvitation.objects.create(
        friendship=friendship,
        sender=sender,
        recipient=recipient,
        name=name,
        pending_key=friendship.id,
    )
    transaction.on_commit(
        lambda: _notify_recipient(recipient.id, sender, invitation, 'created')
    )
    return invitation


@transaction.atomic
def decide_invitation(invitation_id, actor, decision):
    invitation = FriendTripInvitation.objects.select_for_update().select_related(
        'sender', 'recipient', 'friendship'
    ).filter(id=invitation_id).first()
    if invitation is None:
        raise NotFound('Trip invitation not found.')
    if invitation.status != FriendTripInvitation.PENDING:
        raise ValidationError({'invitation': 'This invitation is no longer pending.'})
    if not invitation.friendship or invitation.friendship.status != Friendship.ACCEPTED:
        raise ValidationError({'friend': 'These users are no longer friends.'})
    if decision == 'cancel':
        if invitation.sender_id != actor.id:
            raise PermissionDenied('Only the sender can cancel this invitation.')
        invitation.status = FriendTripInvitation.CANCELLED
    elif decision in {'accept', 'decline'}:
        if invitation.recipient_id != actor.id:
            raise PermissionDenied('Only the recipient can respond.')
        if decision == 'decline':
            invitation.status = FriendTripInvitation.DECLINED
        else:
            group = GroupService.create_group(
                creator=invitation.sender,
                name=invitation.name,
                visibility='private',
                initial_members=[invitation.recipient],
            )
            GroupService.change_member_role(
                group,
                invitation.recipient,
                'plan_creator',
                actor=invitation.sender,
            )
            invitation.group = group
            invitation.status = FriendTripInvitation.ACCEPTED
    else:
        raise ValidationError({'decision': 'Invalid decision.'})
    invitation.pending_key = None
    invitation.save(update_fields=['status', 'group', 'pending_key', 'updated_at'])
    if decision in {'accept', 'decline'}:
        transaction.on_commit(
            lambda: _notify_recipient(
                invitation.sender_id,
                invitation.recipient,
                invitation,
                'accepted' if decision == 'accept' else 'declined',
            )
        )
    return invitation
