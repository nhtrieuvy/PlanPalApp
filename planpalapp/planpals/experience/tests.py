from datetime import datetime, time, timezone as datetime_timezone
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from datetime import timedelta
from unittest.mock import patch

from django.db import close_old_connections
from django.test import TestCase, TransactionTestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient

from planpals.auth.infrastructure.models import User
from planpals.chat.infrastructure.models import Conversation
from planpals.experience.infrastructure.models import GroupPoll, LiveLocationShare
from planpals.experience.infrastructure.repositories import DjangoExperienceRepository
from planpals.experience.infrastructure.realtime import ExperienceRealtimePublisher
from planpals.groups.infrastructure.models import Group, GroupMembership
from planpals.notifications.infrastructure.models import NotificationPreference
from planpals.notifications.infrastructure.repositories import (
    DjangoNotificationRepository,
)


class LiveLocationConcurrencyTests(TransactionTestCase):
    def test_concurrent_starts_leave_only_one_active_share(self):
        user = User.objects.create_user(
            username='location-concurrent', password='password123'
        )
        conversation = Conversation.objects.create(
            conversation_type='direct', user_a=user,
            user_b=User.objects.create_user(
                username='location-peer', password='password123'
            ),
        )
        barrier = Barrier(2)

        def start(mutation_id):
            close_old_connections()
            try:
                barrier.wait(timeout=10)
                return DjangoExperienceRepository().create_live_location(
                    conversation.id,
                    user.id,
                    {
                        'latitude': '10.762622',
                        'longitude': '106.660172',
                        'expires_at': timezone.now() + timedelta(minutes=30),
                        'client_mutation_id': mutation_id,
                    },
                ).id
            finally:
                close_old_connections()

        with ThreadPoolExecutor(max_workers=2) as pool:
            first = pool.submit(start, 'concurrent-1')
            second = pool.submit(start, 'concurrent-2')
            self.assertNotEqual(first.result(timeout=20), second.result(timeout=20))

        self.assertEqual(LiveLocationShare.objects.count(), 2)
        self.assertEqual(LiveLocationShare.objects.filter(is_active=True).count(), 1)


@override_settings(
    CHANNEL_LAYERS={
        'default': {'BACKEND': 'channels.layers.InMemoryChannelLayer'}
    }
)
class ExperienceApiTests(TestCase):
    def setUp(self):
        self.owner = User.objects.create_user(
            username='experience-owner',
            email='owner@example.com',
            password='password123',
        )
        self.member = User.objects.create_user(
            username='experience-member',
            email='member@example.com',
            password='password123',
        )
        self.outsider = User.objects.create_user(
            username='experience-outsider',
            email='outsider@example.com',
            password='password123',
        )
        self.group = Group.objects.create(
            name='Hidden hiking group', admin=self.owner
        )
        GroupMembership.objects.create(
            group=self.group, user=self.owner, role=GroupMembership.ADMIN
        )
        GroupMembership.objects.create(
            group=self.group, user=self.member, role=GroupMembership.MEMBER
        )
        self.conversation = Conversation.objects.create(
            conversation_type='direct',
            user_a=self.owner,
            user_b=self.member,
        )
        self.client = APIClient()

    def test_poll_is_member_only_and_create_is_idempotent(self):
        url = reverse('group-polls', kwargs={'group_id': self.group.id})
        payload = {
            'question': 'Where should we eat?',
            'options': ['Market', 'Restaurant'],
        }

        self.client.force_authenticate(self.outsider)
        self.assertEqual(self.client.get(url).status_code, status.HTTP_403_FORBIDDEN)

        self.client.force_authenticate(self.member)
        first = self.client.post(
            url,
            payload,
            format='json',
            HTTP_X_CLIENT_MUTATION_ID='poll-mutation-1',
        )
        second = self.client.post(
            url,
            payload,
            format='json',
            HTTP_X_CLIENT_MUTATION_ID='poll-mutation-1',
        )
        self.assertEqual(first.status_code, status.HTTP_201_CREATED)
        self.assertEqual(second.status_code, status.HTTP_201_CREATED)
        self.assertEqual(first.json()['id'], second.json()['id'])
        self.assertEqual(GroupPoll.objects.count(), 1)

    def test_poll_vote_replaces_previous_selection(self):
        self.client.force_authenticate(self.member)
        created = self.client.post(
            reverse('group-polls', kwargs={'group_id': self.group.id}),
            {
                'question': 'Pick one',
                'options': ['A', 'B'],
                'allow_multiple': False,
            },
            format='json',
        ).json()
        vote_url = reverse('group-poll-vote', kwargs={'poll_id': created['id']})
        first_id, second_id = [item['id'] for item in created['options']]

        self.assertEqual(
            self.client.post(vote_url, {'option_ids': [first_id]}, format='json').status_code,
            status.HTTP_200_OK,
        )
        result = self.client.post(
            vote_url, {'option_ids': [second_id]}, format='json'
        )
        self.assertEqual(result.json()['selected_option_ids'], [second_id])
        selected_option = next(
            option for option in result.json()['options']
            if option['id'] == second_id
        )
        self.assertEqual(selected_option['voters'][0]['id'], str(self.member.id))

    def test_live_location_requires_consent_and_is_idempotent(self):
        url = reverse(
            'conversation-live-locations',
            kwargs={'conversation_id': self.conversation.id},
        )
        self.client.force_authenticate(self.owner)
        payload = {
            'latitude': 10.762622,
            'longitude': 106.660172,
            'accuracy_meters': 8,
            'duration_minutes': 30,
            'consent': False,
        }
        self.assertEqual(
            self.client.post(url, payload, format='json').status_code,
            status.HTTP_400_BAD_REQUEST,
        )
        payload['consent'] = True
        first = self.client.post(
            url,
            payload,
            format='json',
            HTTP_X_CLIENT_MUTATION_ID='location-mutation-1',
        )
        second = self.client.post(
            url,
            payload,
            format='json',
            HTTP_X_CLIENT_MUTATION_ID='location-mutation-1',
        )
        self.assertEqual(first.status_code, status.HTTP_201_CREATED)
        self.assertEqual(first.json()['id'], second.json()['id'])
        self.assertEqual(LiveLocationShare.objects.count(), 1)

    def test_live_location_normalizes_device_gps_precision(self):
        url = reverse(
            'conversation-live-locations',
            kwargs={'conversation_id': self.conversation.id},
        )
        self.client.force_authenticate(self.owner)

        response = self.client.post(
            url,
            {
                'latitude': 10.7626221234567,
                'longitude': 106.6601729876543,
                'accuracy_meters': 8.12789,
                'duration_minutes': 30,
                'consent': True,
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        share = LiveLocationShare.objects.get()
        self.assertEqual(str(share.latitude), '10.762622')
        self.assertEqual(str(share.longitude), '106.660173')
        self.assertEqual(str(share.accuracy_meters), '8.13')

    def test_global_search_does_not_leak_private_groups(self):
        url = reverse('global-search')
        self.client.force_authenticate(self.member)
        member_result = self.client.get(url, {'q': 'Hidden'}).json()
        self.assertEqual(len(member_result['groups']), 1)

        self.client.force_authenticate(self.outsider)
        outsider_result = self.client.get(url, {'q': 'Hidden'}).json()
        self.assertEqual(outsider_result['groups'], [])


class NotificationPreferenceTests(TestCase):
    def test_overnight_quiet_hours_suppress_push_only(self):
        user = User.objects.create_user(
            username='quiet-user', email='quiet@example.com', password='password123'
        )
        NotificationPreference.objects.create(
            user=user,
            push_enabled=True,
            quiet_hours_enabled=True,
            quiet_hours_start=time(22, 0),
            quiet_hours_end=time(7, 0),
            timezone='UTC',
        )
        repository = DjangoNotificationRepository()

        during_quiet = datetime(2026, 9, 16, 23, tzinfo=datetime_timezone.utc)
        after_quiet = datetime(2026, 9, 16, 9, tzinfo=datetime_timezone.utc)
        self.assertEqual(
            repository.get_push_allowed_user_ids([user.id], during_quiet), []
        )
        self.assertEqual(
            repository.get_push_allowed_user_ids([user.id], after_quiet),
            [user.id],
        )

    def test_daily_digest_candidate_is_emitted_once_per_local_day(self):
        user = User.objects.create_user(
            username='digest-user', email='digest@example.com', password='password123'
        )
        preference = NotificationPreference.objects.create(
            user=user,
            push_enabled=True,
            daily_digest_enabled=True,
            daily_digest_hour=8,
            timezone='UTC',
        )
        repository = DjangoNotificationRepository()
        now = datetime(2026, 9, 16, 8, 5, tzinfo=datetime_timezone.utc)

        self.assertEqual(repository.list_digest_candidates(now), [preference])
        repository.mark_digest_sent(user.id, now)
        self.assertEqual(repository.list_digest_candidates(now), [])


class ExperienceRealtimeResilienceTests(TestCase):
    @patch('planpals.experience.infrastructure.realtime.get_channel_layer')
    def test_redis_failure_does_not_escape_mutation_boundary(self, get_layer):
        layer = get_layer.return_value
        layer.group_send.side_effect = TimeoutError('Redis unavailable')

        ExperienceRealtimePublisher().publish_group(
            '00000000-0000-0000-0000-000000000001',
            'group.poll_created',
            {'poll_id': 'poll-1'},
        )
