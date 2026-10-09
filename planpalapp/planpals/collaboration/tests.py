from datetime import timedelta
from unittest.mock import Mock, patch

from django.test import SimpleTestCase, TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient

from planpals.auth.infrastructure.models import User
from planpals.audit.infrastructure.models import AuditLog
from planpals.budgets.infrastructure.models import Budget
from planpals.collaboration.infrastructure.models import (
    AvailabilityPoll,
    CommentReaction,
    PlanWorkItem,
)
from planpals.collaboration.infrastructure.realtime import CollaborationRealtimePublisher
from planpals.collaboration.application.services import CollaborationService
from planpals.groups.infrastructure.models import Group, GroupMembership
from planpals.plans.infrastructure.models import Plan, PlanActivity


class IcsEscapingTests(SimpleTestCase):
    def test_crlf_and_cr_cannot_inject_calendar_properties(self):
        escaped = CollaborationService._ics_escape('Trip\r\nATTENDEE:evil\rPlace')
        self.assertEqual(escaped, 'Trip\\nATTENDEE:evil\\nPlace')
        self.assertNotIn('\r', escaped)


class CollaborationApiTests(TestCase):
    def setUp(self):
        self.admin = User.objects.create_user(
            username='collab-admin', email='admin@collab.test', password='password123'
        )
        self.creator = User.objects.create_user(
            username='collab-creator', email='creator@collab.test', password='password123'
        )
        self.member = User.objects.create_user(
            username='collab-member', email='member@collab.test', password='password123'
        )
        self.outsider = User.objects.create_user(
            username='collab-outsider', email='outsider@collab.test', password='password123'
        )
        self.group = Group.objects.create(name='Collaboration', admin=self.admin)
        GroupMembership.objects.bulk_create([
            GroupMembership(group=self.group, user=self.admin, role=GroupMembership.ADMIN),
            GroupMembership(group=self.group, user=self.creator, role=GroupMembership.PLAN_CREATOR),
            GroupMembership(group=self.group, user=self.member, role=GroupMembership.MEMBER),
        ])
        now = timezone.now() + timedelta(days=5)
        self.plan = Plan.objects.create(
            title='Trip', creator=self.creator, group=self.group,
            start_date=now, end_date=now + timedelta(days=2),
        )
        Budget.objects.create(plan=self.plan)
        self.activity = PlanActivity.objects.create(
            plan=self.plan, title='Museum', activity_type='sightseeing',
            start_time=now + timedelta(hours=1),
            end_time=now + timedelta(hours=3),
        )
        self.client = APIClient()

    def authenticate(self, user):
        self.client.force_authenticate(user)

    def test_poll_permissions_vote_and_closed_guard(self):
        url = reverse('group-availability-polls', kwargs={'group_id': self.group.id})
        start = timezone.now() + timedelta(days=7)
        payload = {
            'title': 'Choose a weekend',
            'options': [
                {'start_at': start.isoformat(), 'end_at': (start + timedelta(hours=4)).isoformat()},
                {'start_at': (start + timedelta(days=1)).isoformat(),
                 'end_at': (start + timedelta(days=1, hours=4)).isoformat()},
            ],
        }

        self.authenticate(self.member)
        self.assertEqual(self.client.post(url, payload, format='json').status_code, status.HTTP_403_FORBIDDEN)

        self.authenticate(self.creator)
        created = self.client.post(url, payload, format='json')
        self.assertEqual(created.status_code, status.HTTP_201_CREATED)
        self.assertTrue(AuditLog.objects.filter(
            action='CREATE_AVAILABILITY_POLL', resource_id=self.group.id,
        ).exists())
        poll_id = created.data['id']
        option_id = created.data['options'][0]['id']

        self.authenticate(self.member)
        vote_url = reverse('availability-poll-vote', kwargs={'poll_id': poll_id})
        voted = self.client.post(vote_url, {'option_id': option_id, 'status': 'available'}, format='json')
        self.assertEqual(voted.status_code, status.HTTP_200_OK)
        changed_vote = self.client.post(
            vote_url, {'option_id': option_id, 'status': 'maybe'}, format='json'
        )
        self.assertEqual(changed_vote.status_code, status.HTTP_200_OK)
        refreshed = self.client.get(url)
        changed_option = next(
            option for option in refreshed.data[0]['options']
            if option['id'] == option_id
        )
        self.assertEqual(changed_option['votes'][0]['status'], 'maybe')
        self.assertEqual(
            changed_option['votes'][0]['user']['id'], str(self.member.id)
        )

        AvailabilityPoll.objects.filter(id=poll_id).update(is_closed=True)
        closed = self.client.post(vote_url, {'option_id': option_id, 'status': 'maybe'}, format='json')
        self.assertEqual(closed.status_code, status.HTTP_409_CONFLICT)

        self.authenticate(self.outsider)
        self.assertEqual(self.client.get(url).status_code, status.HTTP_403_FORBIDDEN)

    def test_assignee_can_update_only_progress(self):
        url = reverse('plan-work-items', kwargs={'plan_id': self.plan.id})
        payload = {
            'title': 'Bring passports', 'item_type': 'checklist',
            'assignee_id': str(self.member.id), 'due_at': self.plan.start_date.isoformat(),
        }
        self.authenticate(self.creator)
        created = self.client.post(url, payload, format='json')
        self.assertEqual(created.status_code, status.HTTP_201_CREATED)
        self.assertTrue(AuditLog.objects.filter(
            action='CREATE_WORK_ITEM', resource_id=self.plan.id,
        ).exists())
        item_id = created.data['id']

        self.authenticate(self.member)
        detail_url = reverse('plan-work-item-detail', kwargs={'item_id': item_id})
        progress = self.client.patch(detail_url, {'status': 'done'}, format='json')
        self.assertEqual(progress.status_code, status.HTTP_200_OK)
        self.assertEqual(progress.data['status'], 'done')
        self.assertIsNotNone(PlanWorkItem.objects.get(id=item_id).completed_at)

        forbidden = self.client.patch(detail_url, {'title': 'Changed'}, format='json')
        self.assertEqual(forbidden.status_code, status.HTTP_403_FORBIDDEN)

        self.authenticate(self.creator)
        invalid = self.client.post(url, {
            'title': 'Invalid assignment',
            'assignee_id': str(self.outsider.id),
        }, format='json')
        self.assertEqual(invalid.status_code, status.HTTP_409_CONFLICT)

    def test_comment_reaction_and_pin_permissions(self):
        url = reverse('plan-comments', kwargs={'plan_id': self.plan.id})
        self.authenticate(self.member)
        created = self.client.post(url, {
            'body': 'Can we start earlier?',
            'activity_id': str(self.activity.id),
            'mention_user_ids': [str(self.creator.id)],
        }, format='json')
        self.assertEqual(created.status_code, status.HTTP_201_CREATED)
        self.assertTrue(AuditLog.objects.filter(
            action='CREATE_COMMENT', resource_id=self.plan.id,
        ).exists())
        comment_id = created.data['id']

        reacted = self.client.post(
            reverse('plan-comment-react', kwargs={'comment_id': comment_id}),
            {'reaction': 'like'}, format='json',
        )
        self.assertEqual(reacted.status_code, status.HTTP_200_OK)
        changed_reaction = self.client.post(
            reverse('plan-comment-react', kwargs={'comment_id': comment_id}),
            {'reaction': 'love'}, format='json',
        )
        self.assertEqual(changed_reaction.status_code, status.HTTP_200_OK)
        self.assertEqual(CommentReaction.objects.filter(comment_id=comment_id).count(), 1)
        self.assertEqual(CommentReaction.objects.get(comment_id=comment_id).reaction, 'love')
        self.assertEqual(
            self.client.post(reverse('plan-comment-pin', kwargs={'comment_id': comment_id})).status_code,
            status.HTTP_403_FORBIDDEN,
        )

        self.authenticate(self.creator)
        pinned = self.client.post(reverse('plan-comment-pin', kwargs={'comment_id': comment_id}))
        self.assertEqual(pinned.status_code, status.HTTP_200_OK)
        self.assertTrue(pinned.data['is_pinned'])

    def test_clone_preserves_activity_offsets_and_ics_export(self):
        self.authenticate(self.creator)
        new_start = self.plan.start_date + timedelta(days=30)
        cloned = self.client.post(
            reverse('plan-clone', kwargs={'plan_id': self.plan.id}),
            {'title': 'Trip template', 'start_date': new_start.isoformat(), 'as_template': True},
            format='json',
        )
        self.assertEqual(cloned.status_code, status.HTTP_201_CREATED)
        clone = Plan.objects.get(id=cloned.data['id'])
        self.assertTrue(clone.is_template)
        self.assertTrue(AuditLog.objects.filter(
            action='CLONE_PLAN', resource_id=clone.id,
        ).exists())
        self.assertEqual(clone.activities.count(), 1)
        self.assertEqual(
            clone.activities.first().start_time - clone.start_date,
            self.activity.start_time - self.plan.start_date,
        )
        self.assertTrue(Budget.objects.filter(plan=clone).exists())

        exported = self.client.get(reverse('plan-export-ics', kwargs={'plan_id': self.plan.id}))
        self.assertEqual(exported.status_code, status.HTTP_200_OK)
        self.assertIn('text/calendar', exported['Content-Type'])
        self.assertIn(b'BEGIN:VEVENT', exported.content)
        self.assertIn(b'Museum', exported.content)


class CollaborationRealtimePublisherTests(SimpleTestCase):
    @patch('planpals.collaboration.infrastructure.realtime.get_channel_layer')
    def test_redis_failure_does_not_fail_completed_mutation(self, get_layer):
        layer = Mock()
        layer.group_send.side_effect = TimeoutError('Redis unavailable')
        get_layer.return_value = layer

        publisher = CollaborationRealtimePublisher()

        publisher.publish_plan('plan-id', 'collaboration.updated', {'id': 'item-id'})
        publisher.publish_group('group-id', 'availability.updated', {'id': 'poll-id'})
