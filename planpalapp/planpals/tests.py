from datetime import timedelta
from types import SimpleNamespace
from unittest.mock import Mock, patch

from celery.utils.time import rate as celery_rate
from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.core.exceptions import RequestDataTooBig
from django.urls import reverse
from django.test import RequestFactory, TestCase
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient, APIRequestFactory, force_authenticate

from planpals.analytics.application.factories import get_analytics_service
from planpals.audit.domain.entities import AuditAction, AuditResourceType
from planpals.auth.infrastructure.models import Friendship, User
from planpals.chat.infrastructure.models import ChatMessage, Conversation
from planpals.chat.application.services import ConversationService
from planpals.groups.infrastructure.models import Group, GroupMembership
from planpals.plans.infrastructure.models import Plan, PlanActivity
from planpals.chat.presentation.serializers import ChatMessageSerializer, ConversationSerializer
from planpals.shared.exception_handler import custom_exception_handler
from planpals.plans.presentation.views import PlanViewSet
from planpals.shared.analytics_tasks import cleanup_invalid_fcm_tokens_task


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

    def test_request_data_too_big_is_translated_to_413_response(self):
        response = custom_exception_handler(RequestDataTooBig('too large'), {})

        self.assertEqual(response.status_code, status.HTTP_413_REQUEST_ENTITY_TOO_LARGE)
        self.assertEqual(response.data['error_code'], 'payload_too_large')

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

