"""Production reliability and core-flow regression tests."""

from __future__ import annotations

import json
import logging
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from types import SimpleNamespace
from unittest.mock import patch

from django.core.files.uploadedfile import SimpleUploadedFile
from django.db import close_old_connections
from django.test import TestCase, TransactionTestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient

from planpals.auth.infrastructure.models import User
from planpals.chat.infrastructure.models import ChatMessage, Conversation
from planpals.groups.application.commands import JoinGroupViaInviteCommand
from planpals.groups.application.factories import get_join_group_via_invite_handler
from planpals.groups.infrastructure.models import Group, GroupInvite, GroupMembership
from planpals.shared.domain_exceptions import AlreadyGroupMemberException
from planpals.shared.observability import JsonFormatter, RequestContextFilter


class HealthAndObservabilityTests(TestCase):
    def setUp(self):
        self.client = APIClient()

    def test_liveness_is_public_and_propagates_safe_request_id(self):
        response = self.client.get(
            reverse('health-live'),
            HTTP_X_REQUEST_ID='test-request-1234',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.json()['status'], 'ok')
        self.assertEqual(response['X-Request-ID'], 'test-request-1234')

    def test_invalid_request_id_is_replaced(self):
        response = self.client.get(
            reverse('health-live'),
            HTTP_X_REQUEST_ID='invalid id with spaces',
        )

        self.assertRegex(response['X-Request-ID'], r'^[a-f0-9]{32}$')

    def test_readiness_reports_dependency_failure_without_leaking_details(self):
        with patch(
            'planpals.shared.health._check_database',
            side_effect=RuntimeError('database-password-must-not-leak'),
        ):
            response = self.client.get(reverse('health-ready'))

        self.assertEqual(response.status_code, status.HTTP_503_SERVICE_UNAVAILABLE)
        self.assertEqual(
            response.json()['checks']['database']['status'],
            'unavailable',
        )
        self.assertNotContains(
            response,
            'database-password-must-not-leak',
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        )

    def test_json_logging_masks_credentials(self):
        record = logging.LogRecord(
            name='planpal.test',
            level=logging.ERROR,
            pathname=__file__,
            lineno=1,
            msg='Authorization: Bearer secret-token password=secret-password',
            args=(),
            exc_info=None,
        )
        RequestContextFilter().filter(record)
        payload = json.loads(JsonFormatter().format(record))

        self.assertNotIn('secret-token', payload['message'])
        self.assertNotIn('secret-password', payload['message'])
        self.assertIn('[REDACTED]', payload['message'])

    def test_django_response_log_keeps_request_correlation(self):
        record = logging.LogRecord(
            name='django.request',
            level=logging.WARNING,
            pathname=__file__,
            lineno=1,
            msg='Forbidden',
            args=(),
            exc_info=None,
        )
        record.request = SimpleNamespace(request_id='request-from-http-boundary')

        RequestContextFilter().filter(record)
        payload = json.loads(JsonFormatter().format(record))

        self.assertEqual(payload['request_id'], 'request-from-http-boundary')


class CorePermissionAndUploadTests(TestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username='sprint-admin',
            email='sprint-admin@example.com',
            password='password123',
        )
        self.member = User.objects.create_user(
            username='sprint-member',
            email='sprint-member@example.com',
            password='password123',
        )
        self.outsider = User.objects.create_user(
            username='sprint-outsider',
            email='sprint-outsider@example.com',
            password='password123',
        )
        self.group = Group.objects.create(
            name='Sprint group',
            description='Permission test',
            admin=self.admin,
        )
        GroupMembership.objects.create(
            group=self.group,
            user=self.admin,
            role=GroupMembership.ADMIN,
        )
        GroupMembership.objects.create(
            group=self.group,
            user=self.member,
            role=GroupMembership.MEMBER,
        )
        self.conversation = Conversation.objects.create(
            conversation_type='direct',
            user_a=self.admin,
            user_b=self.member,
        )
        self.client = APIClient()

    def test_only_group_admin_can_manage_invites(self):
        url = reverse('group-invites', kwargs={'group_id': self.group.id})

        self.client.force_authenticate(self.member)
        member_response = self.client.get(url)
        self.assertEqual(member_response.status_code, status.HTTP_403_FORBIDDEN)

        self.client.force_authenticate(self.outsider)
        outsider_response = self.client.post(url, {}, format='json')
        self.assertEqual(outsider_response.status_code, status.HTTP_403_FORBIDDEN)

        self.client.force_authenticate(self.admin)
        admin_response = self.client.get(url)
        self.assertEqual(admin_response.status_code, status.HTTP_200_OK)

    def test_conversation_is_not_visible_to_outsider(self):
        self.client.force_authenticate(self.outsider)
        response = self.client.get(
            reverse('conversation-detail', kwargs={'pk': self.conversation.id}),
        )
        self.assertEqual(response.status_code, status.HTTP_404_NOT_FOUND)

    @patch('planpals.chat.infrastructure.repositories.cloudinary.uploader.upload')
    def test_audio_upload_api_returns_durable_cloudinary_url(self, upload_mock):
        upload_mock.return_value = {
            'public_id': 'planpal/messages/attachments/sprint-audio',
            'resource_type': 'video',
            'secure_url': (
                'https://res.cloudinary.com/test/video/upload/'
                'planpal/messages/attachments/sprint-audio.mp3'
            ),
        }
        self.client.force_authenticate(self.admin)
        audio = SimpleUploadedFile(
            'voice-note.mp3',
            b'fake-audio-content',
            content_type='audio/mpeg',
        )

        response = self.client.post(
            reverse(
                'conversation-send-message',
                kwargs={'pk': self.conversation.id},
            ),
            {
                'message_type': 'file',
                'content': '',
                'attachment': audio,
            },
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(response.data['message_type'], 'file')
        self.assertEqual(response.data['attachment_name'], 'voice-note.mp3')
        self.assertIn('/video/upload/', response.data['attachment_url'])
        message = ChatMessage.objects.get(id=response.data['id'])
        self.assertEqual(message.attachment_resource_type, 'video')


class ConcurrentInviteJoinTests(TransactionTestCase):
    """Exercise the row lock that protects invite usage and membership creation."""

    def setUp(self):
        self.admin = User.objects.create_user(
            username='concurrent-admin',
            email='concurrent-admin@example.com',
            password='password123',
        )
        self.joiner = User.objects.create_user(
            username='concurrent-joiner',
            email='concurrent-joiner@example.com',
            password='password123',
        )
        self.group = Group.objects.create(
            name='Concurrent public group',
            description='Invite race test',
            visibility='public',
            admin=self.admin,
        )
        GroupMembership.objects.create(
            group=self.group,
            user=self.admin,
            role=GroupMembership.ADMIN,
        )
        self.invite = GroupInvite.objects.create(
            group=self.group,
            token='654321',
            created_by=self.admin,
            expires_at=timezone.now() + timedelta(hours=1),
            max_uses=1,
        )

    def _join_once(self):
        close_old_connections()
        try:
            result = get_join_group_via_invite_handler().handle(
                JoinGroupViaInviteCommand(
                    token=self.invite.token,
                    user_id=self.joiner.id,
                )
            )
            return result.status
        except AlreadyGroupMemberException:
            return 'already_member'
        finally:
            close_old_connections()

    def test_concurrent_duplicate_join_creates_one_membership_and_one_use(self):
        with ThreadPoolExecutor(max_workers=2) as executor:
            outcomes = list(executor.map(lambda _: self._join_once(), range(2)))

        self.assertCountEqual(outcomes, ['joined', 'already_member'])
        self.assertEqual(
            GroupMembership.objects.filter(
                group=self.group,
                user=self.joiner,
            ).count(),
            1,
        )
        self.invite.refresh_from_db()
        self.assertEqual(self.invite.current_uses, 1)
