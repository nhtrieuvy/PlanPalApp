from datetime import datetime, time, timedelta
from decimal import Decimal

from django.core.cache import cache
from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient

from planpals.analytics.application.factories import get_analytics_service
from planpals.analytics.infrastructure.models import DailyMetric as DailyMetricModel
from planpals.audit.application.services import AuditLogService
from planpals.audit.domain.entities import AuditAction, AuditResourceType
from planpals.audit.infrastructure.repositories import DjangoAuditLogRepository
from planpals.groups.infrastructure.models import Group, GroupMembership
from planpals.notifications.infrastructure.models import Notification
from planpals.notifications.domain.entities import NotificationType
from planpals.plans.infrastructure.models import Plan
from planpals.models import User


class AnalyticsTests(TestCase):
    def setUp(self):
        cache.clear()
        self.client = APIClient()
        self.analytics_service = get_analytics_service()
        self.audit_service = AuditLogService(
            audit_log_repo=DjangoAuditLogRepository(),
            audit_log_notification_dispatcher=None,
        )

        self.owner = User.objects.create_user(
            username='analytics-owner',
            password='password123',
            email='owner@example.com',
            is_staff=True,
        )
        self.member = User.objects.create_user(
            username='analytics-member',
            password='password123',
            email='member@example.com',
        )
        self.previous_user = User.objects.create_user(
            username='analytics-previous',
            password='password123',
            email='previous@example.com',
        )

        self.group = Group.objects.create(
            name='Analytics Group',
            description='Group for analytics tests',
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
            title='Analytics Plan',
            description='Plan for analytics tests',
            creator=self.owner,
            group=self.group,
            start_date=start,
            end_date=end,
            is_public=False,
        )

    def test_daily_aggregation_computes_expected_metrics(self):
        metric_date = timezone.localdate() - timedelta(days=1)
        target_dt = timezone.make_aware(datetime.combine(metric_date, time(hour=10)))
        earlier_dt = timezone.make_aware(
            datetime.combine(metric_date - timedelta(days=20), time(hour=9))
        )

        created_log = self.audit_service.log_action(
            user=self.owner,
            action=AuditAction.CREATE_PLAN.value,
            resource_type=AuditResourceType.PLAN.value,
            resource_id=self.plan.id,
            metadata={'title': self.plan.title},
        )
        self._set_created_at(created_log, target_dt)

        completed_log = self.audit_service.log_action(
            user=self.owner,
            action=AuditAction.COMPLETE_PLAN.value,
            resource_type=AuditResourceType.PLAN.value,
            resource_id=self.plan.id,
            metadata={'title': self.plan.title},
        )
        self._set_created_at(completed_log, target_dt + timedelta(minutes=10))

        join_log = self.audit_service.log_action(
            user=self.member,
            action=AuditAction.JOIN_GROUP.value,
            resource_type=AuditResourceType.GROUP.value,
            resource_id=self.group.id,
            metadata={'group_name': self.group.name},
        )
        self._set_created_at(join_log, target_dt + timedelta(minutes=20))

        historical_log = self.audit_service.log_action(
            user=self.previous_user,
            action=AuditAction.JOIN_GROUP.value,
            resource_type=AuditResourceType.GROUP.value,
            resource_id=self.group.id,
            metadata={'group_name': self.group.name},
        )
        self._set_created_at(historical_log, earlier_dt)

        first_notification = Notification.objects.create(
            user=self.owner,
            type=NotificationType.PLAN_UPDATED.value,
            title='Plan updated',
            message='Plan updated',
            data={'plan_id': str(self.plan.id)},
        )
        self._set_created_at(first_notification, target_dt)

        second_notification = Notification.objects.create(
            user=self.member,
            type=NotificationType.GROUP_JOIN.value,
            title='Group activity',
            message='Joined group',
            data={'group_id': str(self.group.id)},
        )
        self._set_created_at(second_notification, target_dt + timedelta(minutes=5))

        notification_open_log = self.audit_service.log_action(
            user=self.owner,
            action=AuditAction.NOTIFICATION_OPENED.value,
            resource_type=AuditResourceType.NOTIFICATION.value,
            resource_id=first_notification.id,
            metadata={'notification_count': 2, 'bulk': True},
        )
        self._set_created_at(notification_open_log, target_dt + timedelta(minutes=30))

        metric = self.analytics_service.aggregate_daily_metrics(metric_date)

        self.assertEqual(metric.metric_date, metric_date)
        self.assertEqual(metric.active_users, 2)
        self.assertEqual(metric.monthly_active_users, 3)
        self.assertEqual(metric.plans_created, 1)
        self.assertEqual(metric.plans_completed, 1)
        self.assertEqual(metric.group_joins, 1)
        self.assertEqual(metric.notifications_sent, 2)
        self.assertEqual(metric.notifications_opened, 2)
        self.assertEqual(metric.notification_open_rate, 100.0)
        self.assertEqual(metric.plan_creation_rate, 50.0)
        self.assertEqual(metric.plan_completion_rate, 50.0)
        self.assertEqual(metric.group_join_rate, 50.0)

    def test_analytics_endpoints_return_expected_payloads(self):
        today = timezone.localdate()
        yesterday = today - timedelta(days=1)
        two_days_ago = today - timedelta(days=2)

        DailyMetricModel.objects.create(
            date=two_days_ago,
            active_users=6,
            monthly_active_users=12,
            plans_created=3,
            plans_completed=1,
            group_joins=2,
            notifications_sent=6,
            notifications_opened=3,
            notification_open_rate=Decimal('50.00'),
            plan_creation_rate=Decimal('50.00'),
            plan_completion_rate=Decimal('16.67'),
            group_join_rate=Decimal('33.33'),
        )
        DailyMetricModel.objects.create(
            date=yesterday,
            active_users=8,
            monthly_active_users=18,
            plans_created=5,
            plans_completed=3,
            group_joins=4,
            notifications_sent=8,
            notifications_opened=4,
            notification_open_rate=Decimal('50.00'),
            plan_creation_rate=Decimal('62.50'),
            plan_completion_rate=Decimal('37.50'),
            group_join_rate=Decimal('50.00'),
        )

        event_time = timezone.make_aware(datetime.combine(yesterday, time(hour=11)))
        create_log = self.audit_service.log_action(
            user=self.owner,
            action=AuditAction.CREATE_PLAN.value,
            resource_type=AuditResourceType.PLAN.value,
            resource_id=self.plan.id,
            metadata={'title': self.plan.title},
        )
        self._set_created_at(create_log, event_time)
        join_log = self.audit_service.log_action(
            user=self.member,
            action=AuditAction.JOIN_GROUP.value,
            resource_type=AuditResourceType.GROUP.value,
            resource_id=self.group.id,
            metadata={'group_name': self.group.name},
        )
        self._set_created_at(join_log, event_time + timedelta(minutes=10))

        self.client.force_authenticate(self.owner)

        summary_response = self.client.get(
            reverse('analytics-summary'),
            {'range': '7d'},
        )
        self.assertEqual(summary_response.status_code, status.HTTP_200_OK)
        self.assertIn('dau', summary_response.data)
        self.assertIn('totals', summary_response.data)
        self.assertIn('plan_creation_rate', summary_response.data)
        self.assertEqual(summary_response.data['range'], '7d')

        timeseries_response = self.client.get(
            reverse('analytics-timeseries'),
            {'metric': 'dau', 'range': '7d'},
        )
        self.assertEqual(timeseries_response.status_code, status.HTTP_200_OK)
        self.assertEqual(timeseries_response.data['metric'], 'dau')
        self.assertEqual(len(timeseries_response.data['points']), 7)

        top_response = self.client.get(
            reverse('analytics-top'),
            {'range': '30d', 'limit': 3},
        )
        self.assertEqual(top_response.status_code, status.HTTP_200_OK)
        self.assertIn('plans', top_response.data)
        self.assertIn('groups', top_response.data)
        self.assertGreaterEqual(len(top_response.data['plans']), 1)
        self.assertGreaterEqual(len(top_response.data['groups']), 1)

    def test_analytics_endpoints_require_staff_permissions(self):
        DailyMetricModel.objects.create(
            date=timezone.localdate() - timedelta(days=1),
            active_users=8,
            monthly_active_users=18,
            plans_created=5,
            plans_completed=3,
            group_joins=4,
            notifications_sent=8,
            notifications_opened=4,
            notification_open_rate=Decimal('50.00'),
            plan_creation_rate=Decimal('62.50'),
            plan_completion_rate=Decimal('37.50'),
            group_join_rate=Decimal('50.00'),
        )

        self.client.force_authenticate(self.member)
        response = self.client.get(reverse('analytics-summary'), {'range': '7d'})
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_summary_cache_is_invalidated_after_reaggregation(self):
        metric_date = timezone.localdate()
        stale_row = DailyMetricModel.objects.create(
            date=metric_date,
            active_users=1,
            monthly_active_users=1,
            plans_created=0,
            plans_completed=0,
            expenses_created=0,
            expense_total_amount=Decimal('0.00'),
            group_joins=0,
            notifications_sent=0,
            notifications_opened=0,
            notification_open_rate=Decimal('0.00'),
            plan_creation_rate=Decimal('0.00'),
            plan_completion_rate=Decimal('0.00'),
            group_join_rate=Decimal('0.00'),
        )
        self.analytics_service.get_dashboard_summary('7d')

        expense_log = self.audit_service.log_action(
            user=self.owner,
            action=AuditAction.CREATE_EXPENSE.value,
            resource_type=AuditResourceType.PLAN.value,
            resource_id=self.plan.id,
            metadata={
                'plan_id': str(self.plan.id),
                'amount': '175000.00',
                'category': 'Food',
            },
        )
        self._set_created_at(expense_log, timezone.make_aware(datetime.combine(metric_date, time(hour=12))))

        metric = self.analytics_service.aggregate_daily_metrics(metric_date)
        summary = self.analytics_service.get_dashboard_summary('7d')

        stale_row.refresh_from_db()
        self.assertEqual(metric.expenses_created, 1)
        self.assertEqual(metric.expense_total_amount, 175000.0)
        self.assertEqual(summary.totals.expenses_created, 1)
        self.assertEqual(summary.totals.expense_total_amount, 175000.0)

    def _set_created_at(self, instance, created_at):
        instance.__class__.objects.filter(pk=instance.pk).update(created_at=created_at)
        instance.refresh_from_db()
