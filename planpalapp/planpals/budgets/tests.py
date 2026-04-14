from datetime import timedelta
from decimal import Decimal

from django.test import TestCase
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.exceptions import PermissionDenied
from rest_framework.test import APIClient

from planpals.analytics.application.factories import get_analytics_service
from planpals.audit.domain.entities import AuditAction, AuditResourceType
from planpals.audit.infrastructure.models import AuditLog
from planpals.budgets.application.factories import get_budget_service
from planpals.budgets.infrastructure.models import Budget, Expense
from planpals.groups.infrastructure.models import Group, GroupMembership
from planpals.notifications.domain.entities import NotificationType
from planpals.notifications.infrastructure.models import Notification
from planpals.plans.application.commands import CreatePlanCommand
from planpals.plans.application.factories import get_create_plan_handler
from planpals.plans.infrastructure.models import Plan
from planpals.models import User


class BudgetTrackingTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.budget_service = get_budget_service()
        self.analytics_service = get_analytics_service()

        self.owner = User.objects.create_user(
            username='budget-owner',
            password='password123',
            email='owner@example.com',
        )
        self.member = User.objects.create_user(
            username='budget-member',
            password='password123',
            email='member@example.com',
        )
        self.outsider = User.objects.create_user(
            username='budget-outsider',
            password='password123',
            email='outsider@example.com',
        )

        self.group = Group.objects.create(
            name='Budget Group',
            description='Group for budget tests',
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
        end = start + timedelta(days=3)
        self.plan = Plan.objects.create(
            title='Budget Plan',
            description='Plan for budget tests',
            creator=self.owner,
            group=self.group,
            start_date=start,
            end_date=end,
            is_public=False,
        )
        self.budget_service.initialize_plan_budget(self.plan.id)

    def test_create_plan_handler_initializes_budget(self):
        handler = get_create_plan_handler()
        start = timezone.now() + timedelta(days=2)
        end = start + timedelta(days=2)

        plan = handler.handle(
            CreatePlanCommand(
                creator_id=self.owner.id,
                title='Handler Budget Plan',
                description='Created through handler',
                plan_type='personal',
                group_id=None,
                start_date=start,
                end_date=end,
                is_public=False,
            )
        )

        budget = Budget.objects.get(plan=plan)
        self.assertEqual(budget.total_budget, Decimal('0'))
        self.assertEqual(budget.currency, 'VND')

    def test_budget_summary_and_audit_logs_are_correct(self):
        self.budget_service.create_or_update_budget(
            self.plan.id,
            self.owner,
            total_budget='1200000',
            currency='vnd',
        )
        self.budget_service.add_expense(
            self.plan.id,
            self.owner,
            amount='200000',
            category='Food',
            description='Lunch',
        )
        self.budget_service.add_expense(
            self.plan.id,
            self.member,
            amount='300000',
            category='Transport',
            description='Taxi',
        )

        summary = self.budget_service.get_budget_summary(self.plan.id, self.owner)

        self.assertEqual(summary.budget.total_budget, Decimal('1200000.00'))
        self.assertEqual(summary.total_spent, Decimal('500000.00'))
        self.assertEqual(summary.remaining_budget, Decimal('700000.00'))
        self.assertEqual(summary.expense_count, 2)
        self.assertEqual(len(summary.breakdown), 2)
        self.assertEqual(summary.breakdown[0].user_id, self.member.id)
        self.assertEqual(summary.breakdown[0].amount, Decimal('300000.00'))
        self.assertEqual(summary.breakdown[1].user_id, self.owner.id)
        self.assertEqual(summary.breakdown[1].amount, Decimal('200000.00'))

        self.assertEqual(
            AuditLog.objects.filter(
                action=AuditAction.UPDATE_BUDGET.value,
                resource_type=AuditResourceType.BUDGET.value,
            ).count(),
            1,
        )
        self.assertEqual(
            AuditLog.objects.filter(
                action=AuditAction.CREATE_EXPENSE.value,
                resource_type=AuditResourceType.EXPENSE.value,
            ).count(),
            2,
        )

    def test_budget_permissions_and_endpoints(self):
        self.budget_service.create_or_update_budget(
            self.plan.id,
            self.owner,
            total_budget='500000',
            currency='VND',
        )

        with self.assertRaises(PermissionDenied):
            self.budget_service.create_or_update_budget(
                self.plan.id,
                self.member,
                total_budget='700000',
                currency='VND',
            )

        self.client.force_authenticate(self.member)
        create_expense_response = self.client.post(
            reverse('plan-expenses', kwargs={'plan_id': self.plan.id}),
            {
                'amount': '150000',
                'category': 'Food',
                'description': 'Dinner',
            },
            format='json',
        )
        self.assertEqual(create_expense_response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(create_expense_response.data['expense']['category'], 'Food')

        self.client.force_authenticate(self.owner)
        budget_response = self.client.get(
            reverse('plan-budget', kwargs={'plan_id': self.plan.id}),
        )
        self.assertEqual(budget_response.status_code, status.HTTP_200_OK)
        self.assertEqual(budget_response.data['expense_count'], 1)
        self.assertEqual(str(budget_response.data['total_spent']), '150000.00')

        expenses_response = self.client.get(
            reverse('plan-expenses', kwargs={'plan_id': self.plan.id}),
            {'page_size': 10},
        )
        self.assertEqual(expenses_response.status_code, status.HTTP_200_OK)
        self.assertEqual(expenses_response.data['count'], 1)
        self.assertEqual(len(expenses_response.data['results']), 1)
        self.assertIsNone(expenses_response.data['next'])

        self.client.force_authenticate(self.outsider)
        forbidden_response = self.client.get(
            reverse('plan-budget', kwargs={'plan_id': self.plan.id}),
        )
        self.assertEqual(forbidden_response.status_code, status.HTTP_403_FORBIDDEN)

    def test_process_expense_notifications_creates_budget_alerts(self):
        self.budget_service.create_or_update_budget(
            self.plan.id,
            self.owner,
            total_budget='10000000',
            currency='VND',
        )
        result = self.budget_service.add_expense(
            self.plan.id,
            self.member,
            amount='8500000',
            category='Hotel',
            description='Large hotel payment',
        )

        outcome = self.budget_service.process_expense_notifications(result.expense.id)

        self.assertEqual(outcome['status'], 'processed')
        self.assertEqual(outcome['notifications_sent'], 2)
        self.assertEqual(
            Notification.objects.filter(
                user=self.owner,
                type=NotificationType.LARGE_EXPENSE.value,
            ).count(),
            1,
        )
        self.assertEqual(
            Notification.objects.filter(
                user=self.owner,
                type=NotificationType.BUDGET_ALERT.value,
            ).count(),
            1,
        )
        self.assertFalse(Notification.objects.filter(user=self.member).exists())

    def test_analytics_aggregation_includes_expense_metrics(self):
        self.budget_service.create_or_update_budget(
            self.plan.id,
            self.owner,
            total_budget='1000000',
            currency='VND',
        )
        self.budget_service.add_expense(
            self.plan.id,
            self.owner,
            amount='250000',
            category='Food',
            description='Analytics expense',
        )

        metric = self.analytics_service.aggregate_daily_metrics(timezone.localdate())

        self.assertEqual(metric.expenses_created, 1)
        self.assertEqual(metric.expense_total_amount, 250000.0)
        self.assertGreaterEqual(metric.active_users, 1)
        self.assertEqual(Expense.objects.filter(plan=self.plan).count(), 1)
