from datetime import timedelta

from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from planpals.auth.application.friend_trips import decide_invitation, send_invitation
from planpals.auth.application.services import UserService
from planpals.auth.infrastructure.models import FriendTripInvitation, Friendship, User
from planpals.groups.infrastructure.models import Group, GroupMembership
from planpals.groups.application.services import GroupService
from planpals.plans.infrastructure.models import Plan, PlanPublication


class JourneyPrivacyTests(TestCase):
    def setUp(self):
        self.owner = User.objects.create_user(
            username='journey-owner', email='owner@example.com', password='password123'
        )
        self.friend = User.objects.create_user(
            username='journey-friend', email='friend@example.com', password='password123'
        )
        self.visitor = User.objects.create_user(
            username='journey-visitor', email='visitor@example.com', password='password123'
        )
        self.client = APIClient()
        self.client.force_authenticate(self.visitor)
        self.start = timezone.now() - timedelta(days=10)
        self.end = timezone.now() - timedelta(days=7)

    def _plan(self, title, group=None, is_public=True):
        return Plan.objects.create(
            title=title,
            creator=self.owner,
            group=group,
            start_date=self.start,
            end_date=self.end,
            status='completed',
            is_public=is_public,
        )

    def test_private_group_is_not_discoverable(self):
        group = Group.objects.create(
            name='Private group', admin=self.owner, visibility='private'
        )
        plan = self._plan('Secret schedule', group=group)

        self.assertFalse(plan.is_public)
        self.assertNotIn(plan, Plan.objects.public())
        self.assertNotIn(plan, Plan.objects.for_user(self.visitor))
        response = self.client.get('/api/v1/plans/public/')
        self.assertEqual(response.status_code, 200)
        self.assertNotIn(str(plan.id), str(response.data))

    def test_group_visibility_change_updates_existing_plan(self):
        group = Group.objects.create(
            name='Changing group', admin=self.owner, visibility='private'
        )
        GroupMembership.objects.create(
            group=group, user=self.owner, role=GroupMembership.ADMIN
        )
        plan = self._plan('Changing itinerary', group=group)

        GroupService.update_group(group, self.owner, visibility='public')
        plan.refresh_from_db()
        self.assertTrue(plan.is_public)

        group.refresh_from_db()
        GroupService.update_group(group, self.owner, visibility='private')
        plan.refresh_from_db()
        self.assertFalse(plan.is_public)

    def test_legacy_public_plan_does_not_auto_publish_to_profile(self):
        plan = self._plan('Legacy public trip')
        response = self.client.get(
            f'/api/v1/users/{self.owner.id}/published-profile/'
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data['publications'], [])
        self.assertIn(plan, Plan.objects.public())

        self.client.force_authenticate(user=None)
        anonymous = self.client.get(
            f'/api/v1/users/{self.owner.id}/published-profile/'
        )
        self.assertIn(anonymous.status_code, (401, 403))

    def test_publication_never_serializes_private_plan_fields(self):
        plan = self._plan('Published trip')
        plan.description = 'private booking reference'
        plan.save()
        publication = PlanPublication.objects.create(
            plan=plan,
            destination='Da Nang',
            summary='A weekend by the sea',
            highlights=[{'source_id': 'internal-id', 'title': 'Beach', 'place': 'Da Nang'}],
        )
        response = self.client.get(
            f'/api/v1/users/{self.owner.id}/published-profile/'
        )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(len(response.data['publications']), 1)
        self.assertNotIn('private booking reference', str(response.data))
        self.assertNotIn('email', response.data['user'])
        self.assertNotIn('start_date', response.data['publications'][0])
        self.assertNotIn('internal-id', str(response.data))
        preview = self.client.get(f'/api/v1/publications/{publication.id}/')
        self.assertEqual(preview.status_code, 200)
        self.assertNotIn('internal-id', str(preview.data))

    def test_only_owner_can_publish_completed_personal_plan(self):
        plan = self._plan('Owner trip')
        url = f'/api/v1/plans/{plan.id}/publication/'
        payload = {'destination': 'Hue', 'summary': 'A quiet weekend'}
        denied = self.client.put(url, payload, format='json')
        self.assertEqual(denied.status_code, 404)

        self.client.force_authenticate(self.owner)
        created = self.client.put(url, payload, format='json')
        self.assertEqual(created.status_code, 201)
        self.assertEqual(created.data['destination'], 'Hue')

        plan.status = 'upcoming'
        plan.save()
        rejected = self.client.put(url, payload, format='json')
        self.assertEqual(rejected.status_code, 400)

    def test_friend_trip_is_created_only_after_acceptance(self):
        friendship = Friendship.objects.create(
            user_a=self.owner,
            user_b=self.friend,
            initiator=self.owner,
            status=Friendship.ACCEPTED,
        )
        invitation = send_invitation(self.owner, self.friend, 'Sea escape')
        self.assertEqual(invitation.friendship_id, friendship.id)
        self.assertIsNone(invitation.group_id)
        accepted = decide_invitation(invitation.id, self.friend, 'accept')
        self.assertEqual(accepted.group.visibility, 'private')
        self.assertEqual(
            GroupMembership.objects.get(
                group=accepted.group, user=self.friend
            ).role,
            GroupMembership.PLAN_CREATOR,
        )
        plan = self._plan('Two-person itinerary', group=accepted.group)
        self.assertTrue(plan.can_edit_by_id(self.friend.id))
        self.assertFalse(plan.can_edit_by_id(self.visitor.id))

        plan.status = 'upcoming'
        plan.save()
        self.client.force_authenticate(self.friend)
        edit = self.client.patch(
            f'/api/v1/plans/{plan.id}/', {'title': 'Our itinerary'}, format='json'
        )
        self.assertEqual(edit.status_code, 200)
        self.assertEqual(edit.data['title'], 'Our itinerary')
        remove = self.client.delete(f'/api/v1/plans/{plan.id}/')
        self.assertEqual(remove.status_code, 403)

        success, _ = UserService.unfriend_user(self.owner, self.friend)
        self.assertTrue(success)
        self.assertTrue(plan.can_edit_by_id(self.friend.id))

    def test_unfriend_cancels_pending_trip_invitation(self):
        Friendship.objects.create(
            user_a=self.owner,
            user_b=self.friend,
            initiator=self.owner,
            status=Friendship.ACCEPTED,
        )
        invitation = send_invitation(self.owner, self.friend, 'Maybe later')
        success, _ = UserService.unfriend_user(self.owner, self.friend)
        self.assertTrue(success)
        invitation.refresh_from_db()
        self.assertEqual(invitation.status, FriendTripInvitation.CANCELLED)
        self.assertIsNone(invitation.pending_key)
