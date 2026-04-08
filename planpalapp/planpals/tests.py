from datetime import timedelta

from django.test import RequestFactory, TestCase
from django.utils import timezone
from rest_framework.test import APIRequestFactory, force_authenticate

from planpals.auth.infrastructure.models import User
from planpals.chat.infrastructure.models import ChatMessage, Conversation
from planpals.chat.presentation.serializers import ConversationSerializer
from planpals.plans.infrastructure.models import Plan, PlanActivity
from planpals.plans.presentation.views import PlanViewSet


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

