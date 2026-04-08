from datetime import timedelta
from unittest.mock import patch

from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient

from planpals.audit.application.services import AuditLogService
from planpals.audit.domain.entities import AuditAction, AuditResourceType
from planpals.audit.infrastructure.repositories import DjangoAuditLogRepository
from planpals.models import Group, GroupMembership, Plan, User
from planpals.notifications.application.factories import (
    get_audit_log_notification_dispatcher,
    get_notification_service,
)
from planpals.notifications.domain.entities import NotificationType
from planpals.notifications.infrastructure.models import Notification


class NotificationTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.notification_service = get_notification_service()
        self.audit_service = AuditLogService(
            audit_log_repo=DjangoAuditLogRepository(),
            audit_log_notification_dispatcher=None,
        )

        self.owner = User.objects.create_user(
            username='owner',
            password='password123',
            email='owner@example.com',
        )
        self.member = User.objects.create_user(
            username='member',
            password='password123',
            email='member@example.com',
        )
        self.viewer = User.objects.create_user(
            username='viewer',
            password='password123',
            email='viewer@example.com',
        )

        self.group = Group.objects.create(
            name='Notification Group',
            description='Group for notification tests',
            admin=self.owner,
        )
        GroupMembership.objects.create(
            group=self.group,
            user=self.owner,
            role=GroupMembership.ADMIN,
        )
        GroupMembership.objects.create(
            group=self.group,
            user=self.member,
            role=GroupMembership.MEMBER,
        )

        start = timezone.now() + timedelta(days=1)
        end = start + timedelta(days=2)
        self.plan = Plan.objects.create(
            title='Notification Plan',
            description='Plan for notification tests',
            creator=self.owner,
            group=self.group,
            start_date=start,
            end_date=end,
            is_public=False,
        )

    def test_notify_creates_notification(self):
        notification = self.notification_service.notify(
            user_id=self.owner.id,
            notification_type=NotificationType.PLAN_UPDATED.value,
            data={
                'actor_name': 'Plan Owner',
                'plan_title': self.plan.title,
                'change_type': 'updated',
            },
            send_push=False,
        )

        self.assertEqual(Notification.objects.count(), 1)
        self.assertEqual(notification.user_id, self.owner.id)
        self.assertEqual(notification.type, NotificationType.PLAN_UPDATED.value)
        self.assertEqual(notification.title, 'Plan updated')
        self.assertFalse(notification.is_read)

    def test_list_filter_and_mark_read_endpoints(self):
        self.notification_service.notify(
            user_id=self.owner.id,
            notification_type=NotificationType.GROUP_JOIN.value,
            data={
                'actor_name': 'New Member',
                'group_name': self.group.name,
                'membership_event': 'join',
            },
            send_push=False,
        )
        second_notification = self.notification_service.notify(
            user_id=self.owner.id,
            notification_type=NotificationType.ROLE_CHANGED.value,
            data={
                'group_name': self.group.name,
                'new_role': 'admin',
            },
            send_push=False,
        )

        self.client.force_authenticate(self.owner)

        list_response = self.client.get(
            reverse('notification-list'),
            {'is_read': 'false'},
        )
        self.assertEqual(list_response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(list_response.data['results']), 2)
        self.assertEqual(list_response.data['unread_count'], 2)

        mark_read_response = self.client.patch(
            reverse('notification-mark-read', kwargs={'pk': str(second_notification.id)}),
        )
        self.assertEqual(mark_read_response.status_code, status.HTTP_200_OK)

        unread_response = self.client.get(reverse('notification-unread-count'))
        self.assertEqual(unread_response.status_code, status.HTTP_200_OK)
        self.assertEqual(unread_response.data['unread_count'], 1)

        read_all_response = self.client.patch(reverse('notification-mark-all-read'))
        self.assertEqual(read_all_response.status_code, status.HTTP_200_OK)
        self.assertEqual(read_all_response.data['updated_count'], 1)
        self.assertEqual(Notification.objects.filter(user=self.owner, is_read=False).count(), 0)

    @override_settings(CELERY_TASK_ALWAYS_EAGER=True, CELERY_TASK_EAGER_PROPAGATES=True)
    def test_audit_log_join_group_dispatches_group_notification(self):
        self.audit_service = AuditLogService(
            audit_log_repo=DjangoAuditLogRepository(),
            audit_log_notification_dispatcher=lambda audit_log: __import__(
                'planpals.notifications.infrastructure.tasks',
                fromlist=['process_audit_log_notification_task'],
            ).process_audit_log_notification_task.delay(str(audit_log.id)),
        )

        self.audit_service.log_action(
            user=self.member,
            action=AuditAction.JOIN_GROUP.value,
            resource_type=AuditResourceType.GROUP.value,
            resource_id=self.group.id,
            metadata={'group_name': self.group.name},
        )

        owner_notifications = Notification.objects.filter(user=self.owner)
        self.assertEqual(owner_notifications.count(), 1)
        self.assertEqual(owner_notifications.first().type, NotificationType.GROUP_JOIN.value)
        self.assertIn(self.group.name, owner_notifications.first().message)

    def test_notification_open_audit_does_not_enqueue_notification_task(self):
        dispatcher = get_audit_log_notification_dispatcher()
        audit_log = self.audit_service.log_action(
            user=self.owner,
            action=AuditAction.NOTIFICATION_OPENED.value,
            resource_type=AuditResourceType.NOTIFICATION.value,
            resource_id=None,
            metadata={'notification_count': 1, 'bulk': False},
        )

        with patch(
            'planpals.notifications.infrastructure.tasks.process_audit_log_notification_task.delay'
        ) as mocked_delay:
            dispatcher(audit_log)

        mocked_delay.assert_not_called()
