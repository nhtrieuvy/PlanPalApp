import re
from datetime import timedelta
from types import SimpleNamespace
from unittest.mock import Mock, patch
from urllib.parse import parse_qs, urlparse

from celery.utils.time import rate as celery_rate
from django.core import mail
from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.core.exceptions import RequestDataTooBig
from django.urls import reverse
from django.test import RequestFactory, TestCase, override_settings
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient, APIRequestFactory, force_authenticate

from planpals.analytics.application.factories import get_analytics_service
from planpals.audit.domain.entities import AuditAction, AuditResourceType
from planpals.audit.infrastructure.models import AuditLog
from planpals.auth.infrastructure.models import Friendship, User
from planpals.auth.infrastructure.email_verification import EmailVerificationService
from planpals.auth.infrastructure.repositories import DjangoUserRepository
from planpals.chat.infrastructure.models import ChatMessage, Conversation
from planpals.chat.application.services import ConversationService
from planpals.groups.infrastructure.models import Group, GroupMembership
from planpals.plans.infrastructure.models import Plan, PlanActivity
from planpals.plans.application.commands import UpdateActivityCommand
from planpals.plans.application.handlers import UpdateActivityHandler
from planpals.plans.infrastructure.repositories import DjangoPlanActivityRepository
from planpals.chat.presentation.serializers import ChatMessageSerializer, ConversationSerializer
from planpals.shared.exception_handler import custom_exception_handler
from planpals.plans.presentation.views import PlanViewSet
from planpals.shared.domain_exceptions import ActivityVersionConflictException
from planpals.shared.analytics_tasks import cleanup_invalid_fcm_tokens_task
from planpals.shared.presence import (
    register_connection,
    sync_presence_transition,
    unregister_connection,
)


@override_settings(
    EMAIL_BACKEND='django.core.mail.backends.locmem.EmailBackend',
    DEFAULT_FROM_EMAIL='noreply@planpal.test',
)
class AuthEmailVerificationTests(TestCase):
    def setUp(self):
        cache.clear()
        self.client = APIClient()

    def test_registration_stays_pending_until_email_code_is_verified(self):
        response = self.client.post(
            '/api/v1/users/',
            {
                'username': 'verify_me',
                'email': 'verify-me@example.com',
                'password': 'password123',
                'password_confirm': 'password123',
                'first_name': 'Verify',
                'last_name': 'Me',
            },
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(response.data['email_verification_required'])
        self.assertTrue(response.data['verification_email_sent'])

        self.assertFalse(User.objects.filter(username='verify_me').exists())
        self.assertEqual(len(mail.outbox), 1)
        self.assertRegex(mail.outbox[0].body, r'\b\d{6}\b')
        self.assertNotIn('/api/v1/users/verify-email/?', mail.outbox[0].body)

    def test_verify_pending_registration_code_creates_active_verified_user(self):
        register_response = self.client.post(
            '/api/v1/users/',
            {
                'username': 'verify_create',
                'email': 'verify-create@example.com',
                'password': 'password123',
                'password_confirm': 'password123',
                'first_name': 'Verify',
                'last_name': 'Create',
            },
            format='multipart',
        )
        self.assertEqual(register_response.status_code, status.HTTP_201_CREATED)
        self.assertFalse(User.objects.filter(username='verify_create').exists())

        code_match = re.search(r'\b(\d{6})\b', mail.outbox[0].body)
        self.assertIsNotNone(code_match)

        response = self.client.post(
            '/api/v1/users/verify-email/',
            {
                'email': 'verify-create@example.com',
                'code': code_match.group(1),
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        user = User.objects.get(username='verify_create')
        self.assertTrue(user.is_active)
        self.assertTrue(user.is_email_verified)

    def test_verify_pending_registration_with_avatar_still_creates_user(self):
        avatar = SimpleUploadedFile(
            'avatar.jpg',
            b'\xff\xd8\xff\xe0' + b'fake-image-data',
            content_type='image/jpeg',
        )
        register_response = self.client.post(
            '/api/v1/users/',
            {
                'username': 'verify_avatar',
                'email': 'verify-avatar@example.com',
                'password': 'password123',
                'password_confirm': 'password123',
                'first_name': 'Verify',
                'last_name': 'Avatar',
                'avatar': avatar,
            },
            format='multipart',
        )
        self.assertEqual(register_response.status_code, status.HTTP_201_CREATED)
        self.assertFalse(User.objects.filter(username='verify_avatar').exists())

        code_match = re.search(r'\b(\d{6})\b', mail.outbox[0].body)
        self.assertIsNotNone(code_match)

        with patch(
            'planpals.auth.infrastructure.email_verification.cloudinary.uploader.upload',
            return_value={'public_id': 'planpal/avatars/verify_avatar'},
        ) as upload_mock:
            response = self.client.post(
                '/api/v1/users/verify-email/',
                {
                    'email': 'verify-avatar@example.com',
                    'code': code_match.group(1),
                },
                format='json',
            )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        upload_mock.assert_called_once()
        user = User.objects.get(username='verify_avatar')
        self.assertTrue(user.is_active)
        self.assertTrue(user.is_email_verified)
        self.assertEqual(str(user.avatar), 'planpal/avatars/verify_avatar')

    def test_pending_registration_login_returns_email_not_verified(self):
        register_response = self.client.post(
            '/api/v1/users/',
            {
                'username': 'pending_login',
                'email': 'pending-login@example.com',
                'password': 'password123',
                'password_confirm': 'password123',
                'first_name': 'Pending',
                'last_name': 'Login',
            },
            format='multipart',
        )
        self.assertEqual(register_response.status_code, status.HTTP_201_CREATED)
        self.assertFalse(User.objects.filter(username='pending_login').exists())

        response = self.client.post(
            '/o/token/',
            {
                'grant_type': 'password',
                'username': 'pending_login',
                'password': 'password123',
                'client_id': 'any-client',
            },
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.json()['error'], 'email_not_verified')

    def test_verify_email_with_six_digit_code_activates_user(self):
        user = User.objects.create_user(
            username='pending_code_user',
            email='pending-code@example.com',
            password='password123',
            is_active=False,
        )
        EmailVerificationService.send_verification_email(user)
        code_match = re.search(r'\b(\d{6})\b', mail.outbox[0].body)
        self.assertIsNotNone(code_match)

        response = self.client.post(
            '/api/v1/users/verify-email/',
            {
                'email': 'pending-code@example.com',
                'code': code_match.group(1),
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        user.refresh_from_db()
        self.assertTrue(user.is_active)
        self.assertTrue(user.is_email_verified)

    def test_verify_email_activates_user_and_marks_email_verified(self):
        user = User.objects.create_user(
            username='pending_user',
            email='pending@example.com',
            password='password123',
            is_active=False,
        )
        verification_url = EmailVerificationService.build_verification_url(user)
        params = parse_qs(urlparse(verification_url).query)

        response = self.client.get(
            '/api/v1/users/verify-email/',
            {
                'uid': params['uid'][0],
                'token': params['token'][0],
            },
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        user.refresh_from_db()
        self.assertTrue(user.is_active)
        self.assertTrue(user.is_email_verified)

    def test_unverified_user_receives_explicit_login_error(self):
        User.objects.create_user(
            username='blocked_login',
            email='blocked-login@example.com',
            password='password123',
            is_active=False,
        )

        response = self.client.post(
            '/o/token/',
            {
                'grant_type': 'password',
                'username': 'blocked_login',
                'password': 'password123',
                'client_id': 'any-client',
            },
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(response.json()['error'], 'email_not_verified')

    def test_resend_verification_email_is_generic_and_sends_for_pending_user(self):
        User.objects.create_user(
            username='resend_user',
            email='resend@example.com',
            password='password123',
            is_active=False,
        )

        response = self.client.post(
            '/api/v1/users/resend-verification-email/',
            {'email': 'resend@example.com'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(mail.outbox), 1)


class ChatContractTests(TestCase):
    def setUp(self):
        self.factory = RequestFactory()
        self.user_a = User.objects.create_user(
            username='alice',
            password='secret123',
            email='alice@example.com',
        )
        self.user_b = User.objects.create_user(
            username='bob',
            password='secret123',
            email='bob@example.com',
        )

    def test_conversation_serializer_keeps_last_message_id_and_type_from_annotations(self):
        conversation = Conversation.objects.create(
            conversation_type='direct',
            user_a=self.user_a,
            user_b=self.user_b,
        )
        last_message = ChatMessage.objects.create(
            conversation=conversation,
            sender=self.user_b,
            message_type='image',
            content='',
            attachment_name='photo.png',
        )

        request = self.factory.get('/api/v1/conversations/')
        request.user = self.user_a
        instance = (
            Conversation.objects.for_user(self.user_a)
            .with_last_message()
            .get(id=conversation.id)
        )

        payload = ConversationSerializer(
            instance,
            context={'request': request},
        ).data['last_message']

        self.assertEqual(payload['id'], str(last_message.id))
        self.assertEqual(payload['message_type'], 'image')
        self.assertEqual(payload['sender'], self.user_b.username)

    def test_create_message_infers_uploaded_file_metadata(self):
        conversation = Conversation.objects.create(
            conversation_type='direct',
            user_a=self.user_a,
            user_b=self.user_b,
        )
        uploaded = SimpleUploadedFile(
            'receipt.pdf',
            b'file-binary-content',
            content_type='application/pdf',
        )
        fake_message = SimpleNamespace(
            id='message-1',
            conversation=conversation,
            sender=self.user_a,
            message_type='file',
        )

        message_repo = Mock()
        message_repo.create_message.return_value = fake_message
        conversation_repo = Mock()
        realtime_publisher = Mock()
        push_publisher = Mock()

        with (
            patch(
                'planpals.chat.application.services.chat_factories.get_message_repo',
                return_value=message_repo,
            ),
            patch(
                'planpals.chat.application.services.chat_factories.get_conversation_repo',
                return_value=conversation_repo,
            ),
            patch(
                'planpals.chat.application.services.chat_factories.get_realtime_publisher',
                return_value=realtime_publisher,
            ),
            patch(
                'planpals.chat.application.services.chat_factories.get_push_publisher',
                return_value=push_publisher,
            ),
        ):
            ConversationService.create_message(
                conversation=conversation,
                sender=self.user_a,
                validated_data={
                    'message_type': 'file',
                    'content': '',
                    'attachment': uploaded,
                },
            )

        payload = message_repo.create_message.call_args.args[2]
        self.assertEqual(payload['attachment_name'], 'receipt.pdf')
        self.assertEqual(payload['attachment_size'], len(b'file-binary-content'))
        self.assertIs(payload['attachment'], uploaded)

    def test_create_message_uses_location_name_as_fallback_content(self):
        conversation = Conversation.objects.create(
            conversation_type='direct',
            user_a=self.user_a,
            user_b=self.user_b,
        )
        fake_message = SimpleNamespace(
            id='message-2',
            conversation=conversation,
            sender=self.user_a,
            message_type='location',
        )

        message_repo = Mock()
        message_repo.create_message.return_value = fake_message
        conversation_repo = Mock()

        with (
            patch(
                'planpals.chat.application.services.chat_factories.get_message_repo',
                return_value=message_repo,
            ),
            patch(
                'planpals.chat.application.services.chat_factories.get_conversation_repo',
                return_value=conversation_repo,
            ),
            patch(
                'planpals.chat.application.services.chat_factories.get_realtime_publisher',
                return_value=Mock(),
            ),
            patch(
                'planpals.chat.application.services.chat_factories.get_push_publisher',
                return_value=Mock(),
            ),
        ):
            ConversationService.create_message(
                conversation=conversation,
                sender=self.user_a,
                validated_data={
                    'message_type': 'location',
                    'content': '',
                    'latitude': 16.0544,
                    'longitude': 108.2022,
                    'location_name': 'Da Nang',
                },
            )

        payload = message_repo.create_message.call_args.args[2]
        self.assertEqual(payload['content'], 'Da Nang')

    def test_location_message_serializer_accepts_zero_coordinates(self):
        serializer = ChatMessageSerializer(
            data={
                'message_type': 'location',
                'content': '',
                'latitude': 0,
                'longitude': 0,
                'location_name': 'Null Island',
            }
        )

        self.assertTrue(serializer.is_valid(), serializer.errors)

    def test_location_message_serializer_normalizes_high_precision_coordinates(self):
        serializer = ChatMessageSerializer(
            data={
                'message_type': 'location',
                'content': 'Shared location',
                'latitude': 10.766484710146242,
                'longitude': 106.66152901947498,
                'location_name': 'Selected location',
            }
        )

        self.assertTrue(serializer.is_valid(), serializer.errors)
        self.assertEqual(serializer.validated_data['latitude'], 10.766485)
        self.assertEqual(serializer.validated_data['longitude'], 106.661529)

    def test_create_message_persists_location_coordinates_after_rounding(self):
        conversation = Conversation.objects.create(
            conversation_type='direct',
            user_a=self.user_a,
            user_b=self.user_b,
        )

        message = ConversationService.create_message(
            conversation=conversation,
            sender=self.user_a,
            validated_data={
                'message_type': 'location',
                'content': 'Shared location',
                'location_name': 'Selected location',
                'latitude': 10.765745923004474,
                'longitude': 106.66159439831972,
            },
        )

        self.assertEqual(str(message.latitude), '10.765746')
        self.assertEqual(str(message.longitude), '106.661594')

    @patch('planpals.chat.infrastructure.repositories.cloudinary.uploader.upload')
    def test_create_message_uploads_audio_as_video_resource(self, mock_upload):
        conversation = Conversation.objects.create(
            conversation_type='direct',
            user_a=self.user_a,
            user_b=self.user_b,
        )
        mock_upload.return_value = {
            'public_id': 'planpal/messages/attachments/sample-audio',
            'resource_type': 'video',
        }
        uploaded = SimpleUploadedFile(
            'sample.mp3',
            b'fake-audio-data',
            content_type='audio/mpeg',
        )

        message = ConversationService.create_message(
            conversation=conversation,
            sender=self.user_a,
            validated_data={
                'message_type': 'file',
                'content': '',
                'attachment': uploaded,
                'attachment_name': 'sample.mp3',
                'attachment_size': len(b'fake-audio-data'),
            },
        )

        self.assertEqual(message.attachment_resource_type, 'video')
        self.assertIn('/video/upload/', message.attachment_url)

    def test_attachment_url_handles_auto_upload_prefix_without_duplication(self):
        conversation = Conversation.objects.create(
            conversation_type='direct',
            user_a=self.user_a,
            user_b=self.user_b,
        )

        message = ChatMessage(
            conversation=conversation,
            sender=self.user_a,
            message_type='file',
            attachment='auto/upload/planpal/messages/attachments/sample-audio',
            attachment_resource_type='video',
        )

        attachment_url = message.attachment_url

        self.assertIsNotNone(attachment_url)
        self.assertIn('/video/upload/', attachment_url)
        self.assertNotIn('/auto/upload/', attachment_url)

    def test_attachment_url_remains_valid_after_reload_from_db(self):
        conversation = Conversation.objects.create(
            conversation_type='direct',
            user_a=self.user_a,
            user_b=self.user_b,
        )

        message = ChatMessage.objects.create(
            conversation=conversation,
            sender=self.user_a,
            message_type='file',
            attachment='planpal/messages/attachments/sample-audio',
            attachment_resource_type='video',
        )

        reloaded_message = ChatMessage.objects.get(id=message.id)

        self.assertTrue(str(reloaded_message.attachment).startswith('auto/upload/'))
        self.assertIsNotNone(reloaded_message.attachment_url)
        self.assertIn('/video/upload/', reloaded_message.attachment_url)
        self.assertNotIn('/auto/upload/', reloaded_message.attachment_url)

    def test_conversation_messages_return_newest_first_with_cursor(self):
        conversation = Conversation.objects.create(
            conversation_type='direct',
            user_a=self.user_a,
            user_b=self.user_b,
        )

        oldest = ChatMessage.objects.create(
            conversation=conversation,
            sender=self.user_a,
            message_type='text',
            content='oldest',
        )
        middle = ChatMessage.objects.create(
            conversation=conversation,
            sender=self.user_b,
            message_type='text',
            content='middle',
        )
        newest = ChatMessage.objects.create(
            conversation=conversation,
            sender=self.user_a,
            message_type='text',
            content='newest',
        )

        base_time = timezone.now()
        ChatMessage.objects.filter(id=oldest.id).update(
            created_at=base_time - timedelta(minutes=3)
        )
        ChatMessage.objects.filter(id=middle.id).update(
            created_at=base_time - timedelta(minutes=2)
        )
        ChatMessage.objects.filter(id=newest.id).update(
            created_at=base_time - timedelta(minutes=1)
        )

        first_page = ConversationService.get_conversation_messages(
            user=self.user_a,
            conversation_id=str(conversation.id),
            limit=2,
        )

        self.assertEqual([m.id for m in first_page['messages']], [newest.id, middle.id])
        self.assertTrue(first_page['has_more'])
        self.assertEqual(first_page['next_cursor'], str(middle.id))

        second_page = ConversationService.get_conversation_messages(
            user=self.user_a,
            conversation_id=str(conversation.id),
            limit=2,
            before_id=first_page['next_cursor'],
        )

        self.assertEqual([m.id for m in second_page['messages']], [oldest.id])
        self.assertFalse(second_page['has_more'])
        self.assertIsNone(second_page['next_cursor'])


class PlanActivitiesByDateContractTests(TestCase):
    def setUp(self):
        self.factory = APIRequestFactory()
        self.user = User.objects.create_user(
            username='planner',
            password='secret123',
            email='planner@example.com',
        )
        now = timezone.now()
        self.plan = Plan.objects.create(
            title='Test Plan',
            creator=self.user,
            plan_type='personal',
            start_date=now,
            end_date=now + timedelta(days=1),
        )
        PlanActivity.objects.create(
            plan=self.plan,
            title='Morning activity',
            activity_type='other',
            start_time=now.replace(hour=9, minute=0, second=0, microsecond=0),
            end_time=now.replace(hour=10, minute=0, second=0, microsecond=0),
        )
        PlanActivity.objects.create(
            plan=self.plan,
            title='Next day activity',
            activity_type='other',
            start_time=(now + timedelta(days=1)).replace(
                hour=9,
                minute=0,
                second=0,
                microsecond=0,
            ),
            end_time=(now + timedelta(days=1)).replace(
                hour=10,
                minute=0,
                second=0,
                microsecond=0,
            ),
        )

    def test_activities_by_date_returns_requested_date_only(self):
        target_date = self.plan.start_date.date().isoformat()
        view = PlanViewSet.as_view({'get': 'activities_by_date'})
        request = self.factory.get(
            f'/api/v1/plans/{self.plan.id}/activities_by_date/',
            {'date': target_date},
        )
        force_authenticate(request, user=self.user)

        response = view(request, pk=str(self.plan.id))

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['date'], target_date)
        self.assertEqual(len(response.data['activities']), 1)
        self.assertEqual(response.data['activities'][0]['title'], 'Morning activity')


class ActivityCollaborationTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.user = User.objects.create_user(
            username='collab-owner',
            password='secret123',
            email='collab-owner@example.com',
        )
        self.client.force_authenticate(user=self.user)
        now = timezone.now()
        self.plan = Plan.objects.create(
            title='Realtime Plan',
            creator=self.user,
            plan_type='personal',
            start_date=now,
            end_date=now + timedelta(days=2),
        )
        self.activity = PlanActivity.objects.create(
            plan=self.plan,
            title='Original title',
            activity_type='other',
            start_time=now + timedelta(hours=1),
            end_time=now + timedelta(hours=2),
        )

    def test_update_activity_handler_increments_version_and_emits_snapshot(self):
        publisher = Mock()
        handler = UpdateActivityHandler(
            activity_repo=DjangoPlanActivityRepository(),
            event_publisher=publisher,
        )

        updated = handler.handle(
            UpdateActivityCommand(
                activity_id=self.activity.id,
                user_id=self.user.id,
                version=1,
                title='Updated title',
                updated_by_name='collab-owner',
            )
        )

        self.assertEqual(updated.version, 2)
        event = publisher.publish.call_args.args[0]
        self.assertEqual(event.version, 2)
        self.assertEqual(event.updated_fields, ('title',))
        self.assertEqual(event.activity['title'], 'Updated title')

    def test_update_activity_handler_raises_conflict_with_server_state(self):
        handler = UpdateActivityHandler(
            activity_repo=DjangoPlanActivityRepository(),
            event_publisher=Mock(),
        )

        handler.handle(
            UpdateActivityCommand(
                activity_id=self.activity.id,
                user_id=self.user.id,
                version=1,
                title='First update',
                updated_by_name='collab-owner',
            )
        )

        with self.assertRaises(ActivityVersionConflictException) as exc:
            handler.handle(
                UpdateActivityCommand(
                    activity_id=self.activity.id,
                    user_id=self.user.id,
                    version=1,
                    title='Stale update',
                    updated_by_name='collab-owner',
                )
            )

        self.assertEqual(exc.exception.extra['server_version'], 2)
        self.assertEqual(exc.exception.extra['server_state']['title'], 'First update')
        self.assertIn('title', exc.exception.extra['conflicting_fields'])

    def test_activity_update_endpoint_returns_conflict_payload(self):
        first_response = self.client.patch(
            f'/api/v1/activities/{self.activity.id}/',
            {'version': 1, 'title': 'First update'},
            format='json',
        )
        self.assertEqual(first_response.status_code, 200)
        self.assertEqual(first_response.data['activity']['version'], 2)

        conflict_response = self.client.patch(
            f'/api/v1/activities/{self.activity.id}/',
            {'version': 1, 'title': 'Second stale update'},
            format='json',
        )

        self.assertEqual(conflict_response.status_code, 409)
        self.assertEqual(conflict_response.data['error_code'], 'activity_version_conflict')
        self.assertEqual(conflict_response.data['server_version'], 2)
        self.assertEqual(
            conflict_response.data['server_state']['title'],
            'First update',
        )


class SystemRegressionTests(TestCase):
    def setUp(self):
        cache.clear()
        self.client = APIClient()
        self.analytics_service = get_analytics_service()
        self.owner = User.objects.create_user(
            username='system-owner',
            password='secret123',
            email='owner@example.com',
            is_staff=True,
        )
        self.friend_a = User.objects.create_user(
            username='system-friend-a',
            password='secret123',
            email='friend-a@example.com',
        )
        self.friend_b = User.objects.create_user(
            username='system-friend-b',
            password='secret123',
            email='friend-b@example.com',
        )
        self.joiner = User.objects.create_user(
            username='system-joiner',
            password='secret123',
            email='joiner@example.com',
        )
        self.outsider = User.objects.create_user(
            username='system-outsider',
            password='secret123',
            email='outsider@example.com',
        )
        self._make_accepted_friendship(self.owner, self.friend_a)
        self._make_accepted_friendship(self.owner, self.friend_b)

    def test_accept_friend_request_flow_returns_200_and_creates_direct_conversation(self):
        self.client.force_authenticate(self.owner)
        request_response = self.client.post(
            reverse('friend_request'),
            {'friend_id': str(self.joiner.id)},
            format='json',
        )
        self.assertEqual(request_response.status_code, status.HTTP_201_CREATED)
        request_id = request_response.data['friendship']['id']

        self.client.force_authenticate(self.joiner)
        accept_response = self.client.post(
            reverse('friend_request_action', kwargs={'request_id': request_id}),
            {'action': 'accept'},
            format='json',
        )

        self.assertEqual(accept_response.status_code, status.HTTP_200_OK)
        self.assertEqual(accept_response.data['friendship']['status'], Friendship.ACCEPTED)
        self.assertIsNotNone(
            Conversation.objects.get_direct_conversation(self.owner, self.joiner),
        )

    def test_group_create_includes_initial_members_and_returns_detail_payload(self):
        self.client.force_authenticate(self.owner)

        response = self.client.post(
            reverse('group-list'),
            {
                'name': 'Regression Group',
                'description': 'Created through API',
                'initial_members': [
                    str(self.friend_a.id),
                    str(self.friend_b.id),
                ],
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertIn('id', response.data)
        self.assertEqual(response.data['member_count'], 3)
        self.assertEqual(len(response.data['memberships']), 3)
        self.assertTrue(
            GroupMembership.objects.filter(
                group_id=response.data['id'],
                user=self.friend_a,
            ).exists()
        )
        self.assertTrue(
            GroupMembership.objects.filter(
                group_id=response.data['id'],
                user=self.friend_b,
            ).exists()
        )

    def test_group_list_returns_current_membership_count(self):
        group = self._create_group_with_owner('List Count Group')
        GroupMembership.objects.create(
            group=group,
            user=self.friend_a,
            role=GroupMembership.MEMBER,
        )
        GroupMembership.objects.create(
            group=group,
            user=self.friend_b,
            role=GroupMembership.PLAN_CREATOR,
        )

        self.client.force_authenticate(self.owner)
        response = self.client.get(reverse('group-list'))

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        groups = response.data.get('results', response.data)
        payload = next(item for item in groups if item['id'] == str(group.id))
        self.assertEqual(payload['member_count'], 3)

    def test_group_detail_cache_refreshes_after_join(self):
        group = self._create_group_with_owner('Cache Group')

        self.client.force_authenticate(self.owner)
        detail_before = self.client.get(reverse('group-detail', kwargs={'pk': group.id}))
        self.assertEqual(detail_before.status_code, status.HTTP_200_OK)
        self.assertEqual(detail_before.data['member_count'], 1)

        self.client.force_authenticate(self.joiner)
        join_response = self.client.post(reverse('group-join', kwargs={'pk': group.id}))
        self.assertEqual(join_response.status_code, status.HTTP_200_OK)

        self.client.force_authenticate(self.owner)
        detail_after = self.client.get(reverse('group-detail', kwargs={'pk': group.id}))
        self.assertEqual(detail_after.status_code, status.HTTP_200_OK)
        self.assertEqual(detail_after.data['member_count'], 2)
        member_ids = {item['user']['id'] for item in detail_after.data['memberships']}
        self.assertIn(str(self.joiner.id), member_ids)

    def test_group_detail_requires_membership(self):
        group = self._create_group_with_owner('Private Group')

        self.client.force_authenticate(self.outsider)
        response = self.client.get(reverse('group-detail', kwargs={'pk': group.id}))

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_plan_create_returns_detail_payload_with_id(self):
        self.client.force_authenticate(self.owner)
        now = timezone.now() + timedelta(days=1)

        response = self.client.post(
            reverse('plan-list'),
            {
                'title': 'Regression Plan',
                'description': 'Created through API',
                'plan_type': 'personal',
                'is_public': False,
                'start_date': now.isoformat(),
                'end_date': (now + timedelta(days=2)).isoformat(),
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertIn('id', response.data)
        self.assertEqual(response.data['title'], 'Regression Plan')
        self.assertEqual(response.data['creator']['id'], str(self.owner.id))
        self.assertEqual(response.data['plan_type'], 'personal')

    def test_can_cancel_upcoming_plan_only(self):
        now = timezone.now() + timedelta(days=1)
        plan = Plan.objects.create(
            title='Upcoming Cancellation Plan',
            creator=self.owner,
            start_date=now,
            end_date=now + timedelta(days=1),
            status='upcoming',
        )

        self.client.force_authenticate(self.owner)
        response = self.client.post(
            reverse('plan-cancel', kwargs={'pk': str(plan.id)}),
            {'reason': 'Schedule changed'},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(response.data['status'], 'cancelled')

        plan.refresh_from_db()
        self.assertEqual(plan.status, 'cancelled')

        audit_log = AuditLog.objects.get(
            action=AuditAction.UPDATE_PLAN.value,
            resource_type=AuditResourceType.PLAN.value,
            resource_id=plan.id,
        )
        self.assertEqual(audit_log.metadata['changed_fields'], ['status'])
        self.assertEqual(audit_log.metadata['before']['status'], 'upcoming')
        self.assertEqual(audit_log.metadata['after']['status'], 'cancelled')

    def test_cannot_cancel_ongoing_plan(self):
        now = timezone.now()
        plan = Plan.objects.create(
            title='Ongoing Cancellation Guard',
            creator=self.owner,
            start_date=now - timedelta(hours=1),
            end_date=now + timedelta(days=1),
            status='ongoing',
        )

        self.client.force_authenticate(self.owner)
        response = self.client.post(
            reverse('plan-cancel', kwargs={'pk': str(plan.id)}),
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('Only upcoming plans can be cancelled', response.data['error'])

        plan.refresh_from_db()
        self.assertEqual(plan.status, 'ongoing')

    def test_group_plan_create_forces_public_visibility(self):
        group = self._create_group_with_owner('Always Public Group')
        now = timezone.now() + timedelta(days=1)

        self.client.force_authenticate(self.owner)
        response = self.client.post(
            reverse('plan-list'),
            {
                'title': 'Group Plan Must Be Public',
                'description': 'Visibility should be forced by backend',
                'plan_type': 'group',
                'group_id': str(group.id),
                'is_public': False,
                'start_date': now.isoformat(),
                'end_date': (now + timedelta(days=1)).isoformat(),
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertTrue(response.data['is_public'])

        created_plan = Plan.objects.get(id=response.data['id'])
        self.assertEqual(created_plan.plan_type, 'group')
        self.assertTrue(created_plan.is_public)

    def test_activity_create_and_update_are_written_to_plan_audit_log(self):
        now = timezone.now() + timedelta(days=1)
        plan = Plan.objects.create(
            title='Audited Activity Plan',
            creator=self.owner,
            start_date=now,
            end_date=now + timedelta(days=1),
        )

        self.client.force_authenticate(self.owner)
        create_response = self.client.post(
            '/api/v1/activities/',
            {
                'plan_id': str(plan.id),
                'title': 'Book hotel',
                'activity_type': 'resting',
                'start_time': (now + timedelta(hours=1)).isoformat(),
                'end_time': (now + timedelta(hours=2)).isoformat(),
            },
            format='json',
        )

        self.assertEqual(create_response.status_code, status.HTTP_201_CREATED)
        activity_id = create_response.data['id']

        create_log = AuditLog.objects.get(
            action=AuditAction.CREATE_ACTIVITY.value,
            resource_type=AuditResourceType.ACTIVITY.value,
            resource_id=activity_id,
        )
        self.assertEqual(create_log.metadata['plan_id'], str(plan.id))
        self.assertEqual(create_log.metadata['title'], 'Book hotel')

        update_response = self.client.patch(
            f'/api/v1/activities/{activity_id}/',
            {
                'version': create_response.data['version'],
                'title': 'Book resort',
            },
            format='json',
        )

        self.assertEqual(update_response.status_code, status.HTTP_200_OK)
        update_log = AuditLog.objects.get(
            action=AuditAction.UPDATE_ACTIVITY.value,
            resource_type=AuditResourceType.ACTIVITY.value,
            resource_id=activity_id,
        )
        self.assertEqual(update_log.metadata['plan_id'], str(plan.id))
        self.assertEqual(update_log.metadata['updated_fields'], ['title'])
        self.assertEqual(update_log.metadata['before']['title'], 'Book hotel')
        self.assertEqual(update_log.metadata['after']['title'], 'Book resort')

        audit_response = self.client.get(
            f'/api/v1/audit-logs/resource/plan/{plan.id}/',
            format='json',
        )

        self.assertEqual(audit_response.status_code, status.HTTP_200_OK)
        actions = [item['action'] for item in audit_response.data['results']]
        self.assertIn(AuditAction.CREATE_ACTIVITY.value, actions)
        self.assertIn(AuditAction.UPDATE_ACTIVITY.value, actions)

    def test_activity_completion_toggle_is_written_to_plan_audit_log(self):
        now = timezone.now() + timedelta(days=1)
        plan = Plan.objects.create(
            title='Audited Toggle Plan',
            creator=self.owner,
            start_date=now,
            end_date=now + timedelta(days=1),
        )
        activity = PlanActivity.objects.create(
            plan=plan,
            title='Confirm booking',
            activity_type='other',
            start_time=now + timedelta(hours=1),
            end_time=now + timedelta(hours=2),
        )

        self.client.force_authenticate(self.owner)
        response = self.client.post(
            f'/api/v1/plans/{plan.id}/activities/{activity.id}/complete/',
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        update_log = AuditLog.objects.get(
            action=AuditAction.UPDATE_ACTIVITY.value,
            resource_type=AuditResourceType.ACTIVITY.value,
            resource_id=activity.id,
        )
        self.assertEqual(update_log.metadata['plan_id'], str(plan.id))
        self.assertEqual(update_log.metadata['updated_fields'], ['is_completed'])
        self.assertEqual(update_log.metadata['before']['is_completed'], False)
        self.assertEqual(update_log.metadata['after']['is_completed'], True)

    def test_admin_can_grant_plan_creator_and_member_can_create_group_plan(self):
        group = self._create_group_with_owner('Plan Creator Group')
        GroupMembership.objects.create(
            group=group,
            user=self.friend_a,
            role=GroupMembership.MEMBER,
        )

        self.client.force_authenticate(self.friend_a)
        forbidden_response = self.client.post(
            reverse('plan-list'),
            {
                'title': 'Blocked Group Plan',
                'description': 'Member cannot create yet',
                'plan_type': 'group',
                'group_id': str(group.id),
                'start_date': (timezone.now() + timedelta(days=1)).isoformat(),
                'end_date': (timezone.now() + timedelta(days=2)).isoformat(),
            },
            format='json',
        )
        self.assertEqual(forbidden_response.status_code, status.HTTP_403_FORBIDDEN)

        self.client.force_authenticate(self.owner)
        role_response = self.client.post(
            reverse('group-change-role', kwargs={'pk': group.id}),
            {'user_id': str(self.friend_a.id), 'role': GroupMembership.PLAN_CREATOR},
            format='json',
        )
        self.assertEqual(role_response.status_code, status.HTTP_200_OK)
        self.assertEqual(role_response.data['role'], GroupMembership.PLAN_CREATOR)

        membership = GroupMembership.objects.get(group=group, user=self.friend_a)
        self.assertEqual(membership.role, GroupMembership.PLAN_CREATOR)

        self.client.force_authenticate(self.friend_a)
        detail_response = self.client.get(
            reverse('group-detail', kwargs={'pk': group.id}),
            format='json',
        )
        self.assertEqual(detail_response.status_code, status.HTTP_200_OK)
        self.assertEqual(detail_response.data['user_role'], GroupMembership.PLAN_CREATOR)
        self.assertTrue(detail_response.data['can_create_plan'])
        membership_roles = {
            item['user']['id']: item['role']
            for item in detail_response.data['memberships']
        }
        self.assertEqual(
            membership_roles[str(self.friend_a.id)],
            GroupMembership.PLAN_CREATOR,
        )

        plans_response = self.client.get(
            reverse('group-plans', kwargs={'pk': group.id}),
            format='json',
        )
        self.assertEqual(plans_response.status_code, status.HTTP_200_OK)
        self.assertTrue(plans_response.data['can_create_plan'])

        create_response = self.client.post(
            reverse('plan-list'),
            {
                'title': 'Allowed Group Plan',
                'description': 'Plan creator can create',
                'plan_type': 'group',
                'group_id': str(group.id),
                'start_date': (timezone.now() + timedelta(days=1)).isoformat(),
                'end_date': (timezone.now() + timedelta(days=2)).isoformat(),
            },
            format='json',
        )
        self.assertEqual(create_response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(create_response.data['creator']['id'], str(self.friend_a.id))
        self.assertTrue(create_response.data['is_public'])

    def test_set_member_role_handler_invalidates_cached_group_detail_permissions(self):
        from planpals.groups.application.commands import SetMemberRoleCommand
        from planpals.groups.application.handlers import SetMemberRoleHandler
        from planpals.groups.application.services import GroupService
        from planpals.groups.infrastructure.cache import invalidate_group_detail_cache
        from planpals.groups.infrastructure.repositories import DjangoGroupMembershipRepository

        group = self._create_group_with_owner('Handler Permission Cache Group')
        membership = GroupMembership.objects.create(
            group=group,
            user=self.friend_a,
            role=GroupMembership.MEMBER,
        )

        def serialize(current_group):
            current_membership = current_group.get_user_membership(self.friend_a)
            return {
                'user_role': current_membership.role,
                'can_create_plan': current_group.can_create_plans(self.friend_a),
            }

        cached_before = GroupService.get_group_detail_cached(
            group.id,
            self.friend_a.id,
            serialize,
        )
        self.assertEqual(cached_before['user_role'], GroupMembership.MEMBER)
        self.assertFalse(cached_before['can_create_plan'])

        handler = SetMemberRoleHandler(
            DjangoGroupMembershipRepository(),
            Mock(),
            group_cache_invalidator=invalidate_group_detail_cache,
        )
        handler.handle(
            SetMemberRoleCommand(
                group_id=group.id,
                user_id=self.owner.id,
                target_user_id=self.friend_a.id,
                role=GroupMembership.PLAN_CREATOR,
            )
        )

        cached_after = GroupService.get_group_detail_cached(
            group.id,
            self.friend_a.id,
            serialize,
        )
        self.assertEqual(cached_after['user_role'], GroupMembership.PLAN_CREATOR)
        self.assertTrue(cached_after['can_create_plan'])

    def test_plan_creator_cannot_manage_group_roles(self):
        group = self._create_group_with_owner('Role Guard Group')
        GroupMembership.objects.create(
            group=group,
            user=self.friend_a,
            role=GroupMembership.PLAN_CREATOR,
        )
        GroupMembership.objects.create(
            group=group,
            user=self.friend_b,
            role=GroupMembership.MEMBER,
        )

        self.client.force_authenticate(self.friend_a)
        response = self.client.post(
            reverse('group-change-role', kwargs={'pk': group.id}),
            {'user_id': str(self.friend_b.id), 'role': GroupMembership.PLAN_CREATOR},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_group_plan_update_cannot_be_made_private(self):
        group = self._create_group_with_owner('Public Group Update Guard')
        plan = Plan.objects.create(
            title='Existing Group Plan',
            creator=self.owner,
            group=group,
            start_date=timezone.now() + timedelta(days=1),
            end_date=timezone.now() + timedelta(days=2),
            is_public=True,
        )

        self.client.force_authenticate(self.owner)
        response = self.client.patch(
            reverse('plan-detail', kwargs={'pk': str(plan.id)}),
            {'is_public': False},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['is_public'])

        plan.refresh_from_db()
        self.assertTrue(plan.is_public)

    def test_analytics_summary_cache_refreshes_after_aggregate(self):
        plan = Plan.objects.create(
            title='Analytics Cache Plan',
            creator=self.owner,
            plan_type='personal',
            start_date=timezone.now(),
            end_date=timezone.now() + timedelta(days=1),
        )
        summary_before = self.analytics_service.get_dashboard_summary('7d')
        self.assertEqual(summary_before.totals.expenses_created, 0)

        from planpals.audit.application.factories import get_audit_log_service

        get_audit_log_service().log_action(
            user=self.owner,
            action=AuditAction.CREATE_EXPENSE.value,
            resource_type=AuditResourceType.PLAN.value,
            resource_id=plan.id,
            metadata={
                'plan_id': str(plan.id),
                'amount': '125000.00',
                'category': 'Food',
            },
        )
        self.analytics_service.aggregate_daily_metrics(timezone.localdate())

        summary_after = self.analytics_service.get_dashboard_summary('7d')
        self.assertEqual(summary_after.totals.expenses_created, 1)
        self.assertEqual(summary_after.totals.expense_total_amount, 125000.0)

    def test_cleanup_invalid_fcm_tokens_task_uses_worker_safe_rate_limit(self):
        rate_limit = cleanup_invalid_fcm_tokens_task.rate_limit
        if rate_limit:
            self.assertNotIn('/d', rate_limit)
            self.assertGreater(celery_rate(rate_limit), 0)

    def test_cleanup_invalid_fcm_tokens_task_clears_stale_tokens_with_empty_string(self):
        stale_user = User.objects.create_user(
            username='stale-token-user',
            password='password123',
            email='stale-token-user@example.com',
        )
        stale_user.fcm_token = 'stale-token-1234567890'
        stale_user.last_login = timezone.now() - timedelta(days=90)
        stale_user.save(update_fields=['fcm_token', 'last_login'])

        result = cleanup_invalid_fcm_tokens_task.run()

        stale_user.refresh_from_db()
        self.assertEqual(result['status'], 'completed')
        self.assertEqual(result['cleared_tokens'], 1)
        self.assertEqual(stale_user.fcm_token, '')

    def test_user_presence_stays_online_until_last_socket_disconnect(self):
        online_transition = register_connection(self.friend_a.id, 'socket-a')
        sync_presence_transition(
            self.friend_a.id,
            self.friend_a.username,
            online_transition,
        )
        second_online_transition = register_connection(self.friend_a.id, 'socket-b')
        sync_presence_transition(
            self.friend_a.id,
            self.friend_a.username,
            second_online_transition,
        )

        self.friend_a.refresh_from_db()
        self.assertTrue(self.friend_a.is_online)
        self.assertEqual(self.friend_a.online_status, 'online')

        first_disconnect = unregister_connection(self.friend_a.id, 'socket-a')
        sync_presence_transition(
            self.friend_a.id,
            self.friend_a.username,
            first_disconnect,
        )

        self.friend_a.refresh_from_db()
        self.assertTrue(self.friend_a.is_online)
        self.assertEqual(self.friend_a.online_status, 'online')

        final_disconnect = unregister_connection(self.friend_a.id, 'socket-b')
        sync_presence_transition(
            self.friend_a.id,
            self.friend_a.username,
            final_disconnect,
        )

        self.friend_a.refresh_from_db()
        self.assertFalse(self.friend_a.is_online)
        self.assertEqual(self.friend_a.online_status, 'recently_online')
        self.assertTrue(self.friend_a.is_recently_online)

    def test_user_presence_reconnect_restores_online_after_logout_set_offline(self):
        first_connection = register_connection(self.friend_a.id, 'socket-a')
        sync_presence_transition(
            self.friend_a.id,
            self.friend_a.username,
            first_connection,
        )
        self.friend_a.refresh_from_db()
        self.assertTrue(self.friend_a.is_online)

        DjangoUserRepository().set_online_status(self.friend_a.id, False)
        self.friend_a.refresh_from_db()
        self.assertFalse(self.friend_a.is_online)

        reconnect = register_connection(self.friend_a.id, 'socket-b')
        self.assertEqual(reconnect.active_connections, 2)
        self.assertFalse(reconnect.became_online)

        sync_presence_transition(
            self.friend_a.id,
            self.friend_a.username,
            reconnect,
        )

        self.friend_a.refresh_from_db()
        self.assertTrue(self.friend_a.is_online)
        self.assertEqual(self.friend_a.online_status, 'online')

    def test_user_presence_events_publish_to_friends(self):
        from planpals.shared.realtime_publisher import publish_user_online

        with patch('planpals.shared.realtime_publisher.event_publisher.publish_event') as publish:
            publish_user_online(str(self.owner.id), self.owner.username)

        channel_groups = set(publish.call_args.kwargs['channel_groups'])

        self.assertIn(f'user_{self.owner.id}', channel_groups)
        self.assertIn(f'user_{self.friend_a.id}', channel_groups)
        self.assertIn(f'user_{self.friend_b.id}', channel_groups)
        self.assertNotIn(f'user_{self.outsider.id}', channel_groups)

    def test_set_online_status_endpoint_marks_user_online_for_login_presence(self):
        self.client.force_authenticate(self.owner)

        response = self.client.post(
            '/api/v1/users/set_online_status/',
            {'is_online': True},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.owner.refresh_from_db()
        self.assertTrue(self.owner.is_online)
        self.assertTrue(response.data['is_online'])
        self.assertEqual(response.data['online_status'], 'online')

    def test_set_online_status_endpoint_requires_boolean_value(self):
        self.client.force_authenticate(self.owner)

        response = self.client.post(
            '/api/v1/users/set_online_status/',
            {},
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

    def test_set_online_status_handler_publishes_fresh_last_seen_on_offline(self):
        from planpals.auth.application.commands import SetOnlineStatusCommand
        from planpals.auth.application.handlers import SetOnlineStatusHandler

        User.objects.filter(id=self.owner.id).update(is_online=True)
        publisher = Mock()
        handler = SetOnlineStatusHandler(DjangoUserRepository(), publisher)

        handler.handle(
            SetOnlineStatusCommand(user_id=self.owner.id, is_online=False)
        )

        event = publisher.publish.call_args.args[0]
        self.assertIsNotNone(event.last_seen)

    def test_profile_update_does_not_mutate_last_seen(self):
        original_last_seen = timezone.now() - timedelta(days=1)
        User.objects.filter(id=self.friend_a.id).update(
            is_online=False,
            last_seen=original_last_seen,
        )

        updated_user, success = DjangoUserRepository().update_profile(
            self.friend_a.id,
            {'first_name': 'Updated'},
        )

        self.assertTrue(success)
        self.assertEqual(updated_user.first_name, 'Updated')

        self.friend_a.refresh_from_db()
        self.assertEqual(self.friend_a.last_seen, original_last_seen)
        self.assertEqual(self.friend_a.online_status, 'offline')

    def test_request_data_too_big_is_translated_to_413_response(self):
        response = custom_exception_handler(RequestDataTooBig('too large'), {})

        self.assertEqual(response.status_code, status.HTTP_413_REQUEST_ENTITY_TOO_LARGE)
        self.assertEqual(response.data['error_code'], 'payload_too_large')

    def test_delete_group_deletes_owned_group_conversation(self):
        group = self._create_group_with_owner('Delete Conversation Group')
        conversation = Conversation.objects.create(
            conversation_type='group',
            group=group,
            name='Group Chat: Delete Conversation Group',
        )
        self.client.force_authenticate(self.owner)

        response = self.client.delete(f'/api/v1/groups/{group.id}/')

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertFalse(Group.objects.filter(id=group.id).exists())
        self.assertFalse(Conversation.objects.filter(id=conversation.id).exists())

    def _make_accepted_friendship(self, user_a, user_b):
        return Friendship.objects.create(
            user_a=user_a,
            user_b=user_b,
            initiator=user_a,
            status=Friendship.ACCEPTED,
        )

    def _create_group_with_owner(self, name: str) -> Group:
        group = Group.objects.create(
            name=name,
            description='Regression test group',
            admin=self.owner,
        )
        GroupMembership.objects.create(
            group=group,
            user=self.owner,
            role=GroupMembership.ADMIN,
        )
        return group
