from datetime import timedelta

from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient

from planpals.audit.application.services import AuditLogService
from planpals.audit.domain.entities import AuditAction, AuditResourceType
from planpals.audit.infrastructure.models import AuditLog
from planpals.audit.infrastructure.repositories import DjangoAuditLogRepository
from planpals.models import Group, GroupMembership, Plan, User


class AuditLogTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.audit_service = AuditLogService(audit_log_repo=DjangoAuditLogRepository())

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
        self.outsider = User.objects.create_user(
            username='outsider',
            password='password123',
            email='outsider@example.com',
        )

        self.group = Group.objects.create(
            name='Audit Group',
            description='Group for audit tests',
            admin=self.owner,
        )
        GroupMembership.objects.create(group=self.group, user=self.owner, role=GroupMembership.ADMIN)
        GroupMembership.objects.create(group=self.group, user=self.member, role=GroupMembership.MEMBER)

        start = timezone.now() + timedelta(days=1)
        end = start + timedelta(days=2)
        self.plan = Plan.objects.create(
            title='Audit Plan',
            description='Plan for audit tests',
            creator=self.owner,
            group=self.group,
            start_date=start,
            end_date=end,
            is_public=False,
        )

    def test_log_action_creates_entry(self):
        log = self.audit_service.log_action(
            user=self.owner,
            action=AuditAction.CREATE_PLAN.value,
            resource_type=AuditResourceType.PLAN.value,
            resource_id=self.plan.id,
            metadata={
                'title': self.plan.title,
                'group_id': self.group.id,
                'created_at_hint': self.plan.created_at,
            },
        )

        self.assertEqual(AuditLog.objects.count(), 1)
        self.assertEqual(log.action, AuditAction.CREATE_PLAN.value)
        self.assertEqual(log.resource_type, AuditResourceType.PLAN.value)
        self.assertEqual(log.resource_id, self.plan.id)
        self.assertEqual(str(log.metadata['group_id']), str(self.group.id))
        self.assertIn('created_at_hint', log.metadata)

    def test_list_endpoint_filters_by_action_and_user(self):
        self.audit_service.log_action(
            user=self.owner,
            action=AuditAction.CREATE_PLAN.value,
            resource_type=AuditResourceType.PLAN.value,
            resource_id=self.plan.id,
            metadata={'title': 'created'},
        )
        self.audit_service.log_action(
            user=self.owner,
            action=AuditAction.UPDATE_PLAN.value,
            resource_type=AuditResourceType.PLAN.value,
            resource_id=self.plan.id,
            metadata={'title': 'updated'},
        )
        self.audit_service.log_action(
            user=self.member,
            action=AuditAction.JOIN_GROUP.value,
            resource_type=AuditResourceType.GROUP.value,
            resource_id=self.group.id,
            metadata={'group_name': self.group.name},
        )

        self.client.force_authenticate(self.owner)
        response = self.client.get(
            reverse('audit-log-list'),
            {
                'action': AuditAction.UPDATE_PLAN.value,
                'user_id': str(self.owner.id),
            },
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data['results']), 1)
        self.assertEqual(response.data['results'][0]['action'], AuditAction.UPDATE_PLAN.value)
        self.assertEqual(response.data['results'][0]['user_id'], str(self.owner.id))

    def test_group_resource_endpoint_requires_membership(self):
        self.audit_service.log_action(
            user=self.member,
            action=AuditAction.JOIN_GROUP.value,
            resource_type=AuditResourceType.GROUP.value,
            resource_id=self.group.id,
            metadata={'group_name': self.group.name},
        )

        resource_url = reverse(
            'audit-log-resource',
            kwargs={
                'resource_type': AuditResourceType.GROUP.value,
                'resource_id': str(self.group.id),
            },
        )

        self.client.force_authenticate(self.member)
        allowed_response = self.client.get(resource_url)
        self.assertEqual(allowed_response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(allowed_response.data['results']), 1)

        self.client.force_authenticate(self.outsider)
        denied_response = self.client.get(resource_url)
        self.assertEqual(denied_response.status_code, status.HTTP_403_FORBIDDEN)

    def test_plan_resource_endpoint_allows_participants_only(self):
        self.audit_service.log_action(
            user=self.owner,
            action=AuditAction.UPDATE_PLAN.value,
            resource_type=AuditResourceType.PLAN.value,
            resource_id=self.plan.id,
            metadata={'title': self.plan.title},
        )

        resource_url = reverse(
            'audit-log-resource',
            kwargs={
                'resource_type': AuditResourceType.PLAN.value,
                'resource_id': str(self.plan.id),
            },
        )

        self.client.force_authenticate(self.member)
        member_response = self.client.get(resource_url)
        self.assertEqual(member_response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(member_response.data['results']), 1)

        self.client.force_authenticate(self.outsider)
        outsider_response = self.client.get(resource_url)
        self.assertEqual(outsider_response.status_code, status.HTTP_403_FORBIDDEN)
