from datetime import timedelta
from decimal import Decimal
from uuid import uuid4

from django.test import TestCase
from django.core.cache import cache
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.test import APIClient

from planpals.analytics.application.factories import get_analytics_service
from planpals.audit.domain.entities import AuditAction, AuditResourceType
from planpals.audit.infrastructure.models import AuditLog
from planpals.budgets.application.factories import get_budget_service
from planpals.budgets.infrastructure.models import (
    Budget,
    Expense,
    ExpenseParticipant,
    ExpensePayment,
    RecurringExpense,
    Settlement,
)
from planpals.groups.infrastructure.models import Group, GroupMembership
from planpals.notifications.domain.entities import NotificationType
from planpals.notifications.infrastructure.models import Notification
from planpals.plans.application.commands import CreatePlanCommand
from planpals.plans.application.factories import get_create_plan_handler
from planpals.plans.infrastructure.models import Plan
from planpals.models import User
from planpals.shared.cache import CacheKeys


class BudgetTrackingTests(TestCase):
    def setUp(self):
        cache.clear()
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

    def test_budget_mutations_invalidate_budget_and_plan_summary_cache(self):
        budget_key = CacheKeys.budget_summary(self.plan.id)
        plan_key = CacheKeys.plan_summary(self.plan.id)

        cache.set(budget_key, {'stale': True})
        cache.set(plan_key, {'stale': True})
        self.budget_service.create_or_update_budget(
            self.plan.id,
            self.owner,
            total_budget='1000.00',
            currency='VND',
        )
        self.assertIsNone(cache.get(budget_key))
        self.assertIsNone(cache.get(plan_key))

        cache.set(budget_key, {'stale': True})
        cache.set(plan_key, {'stale': True})
        self.budget_service.add_expense(
            self.plan.id,
            self.owner,
            amount='200.00',
            category='Food',
            participants=[
                {'user_id': str(self.owner.id)},
                {'user_id': str(self.member.id)},
            ],
        )
        self.assertIsNone(cache.get(budget_key))
        self.assertIsNone(cache.get(plan_key))

        cache.set(budget_key, {'stale': True})
        cache.set(plan_key, {'stale': True})
        self.budget_service.create_settlement(
            plan_id=self.plan.id,
            actor=self.member,
            from_user_id=self.member.id,
            to_user_id=self.owner.id,
            amount='100.00',
            currency='VND',
        )
        self.assertIsNone(cache.get(budget_key))
        self.assertIsNone(cache.get(plan_key))

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
                resource_type=AuditResourceType.PLAN.value,
                resource_id=self.plan.id,
            ).count(),
            1,
        )
        self.assertEqual(
            AuditLog.objects.filter(
                action=AuditAction.CREATE_EXPENSE.value,
                resource_type=AuditResourceType.PLAN.value,
                resource_id=self.plan.id,
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
        self.assertEqual(expenses_response.data['results'][0]['split_strategy'], 'equal')
        self.assertGreaterEqual(len(expenses_response.data['results'][0]['participants']), 1)
        self.assertIsNone(expenses_response.data['next'])

        balances_response = self.client.get(
            reverse('plan-balances', kwargs={'plan_id': self.plan.id}),
        )
        self.assertEqual(balances_response.status_code, status.HTTP_200_OK)
        self.assertIn('settlement_suggestions', balances_response.data)

        self.client.force_authenticate(self.outsider)
        forbidden_response = self.client.get(
            reverse('plan-budget', kwargs={'plan_id': self.plan.id}),
        )
        self.assertEqual(forbidden_response.status_code, status.HTTP_403_FORBIDDEN)

    def test_equal_split_calculates_participants_and_balances(self):
        result = self.budget_service.add_expense(
            self.plan.id,
            self.owner,
            amount='1200000',
            category='Food',
            description='Shared dinner',
            paid_by_user_id=self.owner.id,
            split_strategy='equal',
            participants=[
                {'user_id': str(self.owner.id)},
                {'user_id': str(self.member.id)},
            ],
        )

        participants = ExpenseParticipant.objects.filter(expense_id=result.expense.id)
        self.assertEqual(participants.count(), 2)
        self.assertTrue(
            participants.filter(user=self.owner, owed_amount=Decimal('600000.00')).exists()
        )
        self.assertTrue(
            participants.filter(user=self.member, owed_amount=Decimal('600000.00')).exists()
        )

        balances = self.budget_service.get_balances(self.plan.id, self.owner)
        by_user = {item.user_id: item for item in balances.balances}
        self.assertEqual(by_user[self.owner.id].net_balance, Decimal('600000.00'))
        self.assertEqual(by_user[self.member.id].net_balance, Decimal('-600000.00'))
        self.assertEqual(len(balances.settlement_suggestions), 1)
        suggestion = balances.settlement_suggestions[0]
        self.assertEqual(suggestion.from_user_id, self.member.id)
        self.assertEqual(suggestion.to_user_id, self.owner.id)
        self.assertEqual(suggestion.amount, Decimal('600000.00'))

    def test_multiple_payment_contributions_calculate_balances_correctly(self):
        result = self.budget_service.add_expense(
            self.plan.id,
            self.owner,
            amount='600.00',
            category='Food',
            split_strategy='equal',
            participants=[
                {'user_id': str(self.owner.id)},
                {'user_id': str(self.member.id)},
            ],
            payments=[
                {'user_id': str(self.owner.id), 'amount': '500.00'},
                {'user_id': str(self.member.id), 'amount': '100.00'},
            ],
        )

        payments = ExpensePayment.objects.filter(expense_id=result.expense.id)
        self.assertEqual(payments.count(), 2)
        self.assertTrue(payments.filter(user=self.owner, amount=Decimal('500.00')).exists())
        self.assertTrue(payments.filter(user=self.member, amount=Decimal('100.00')).exists())

        balances = self.budget_service.get_balances(self.plan.id, self.owner)
        by_user = {item.user_id: item for item in balances.balances}
        self.assertEqual(by_user[self.owner.id].total_paid, Decimal('500.00'))
        self.assertEqual(by_user[self.member.id].total_paid, Decimal('100.00'))
        self.assertEqual(by_user[self.owner.id].net_balance, Decimal('200.00'))
        self.assertEqual(by_user[self.member.id].net_balance, Decimal('-200.00'))
        self.assertEqual(len(balances.settlement_suggestions), 1)
        self.assertEqual(balances.settlement_suggestions[0].amount, Decimal('200.00'))

    def test_plan_balances_aggregate_multiple_expenses(self):
        self.budget_service.add_expense(
            self.plan.id,
            self.owner,
            amount='600.00',
            category='Food',
            split_strategy='equal',
            participants=[
                {'user_id': str(self.owner.id)},
                {'user_id': str(self.member.id)},
            ],
            payments=[{'user_id': str(self.owner.id), 'amount': '600.00'}],
        )
        self.budget_service.add_expense(
            self.plan.id,
            self.member,
            amount='400.00',
            category='Transport',
            split_strategy='equal',
            participants=[
                {'user_id': str(self.owner.id)},
                {'user_id': str(self.member.id)},
            ],
            payments=[{'user_id': str(self.member.id), 'amount': '400.00'}],
        )

        balances = self.budget_service.get_balances(self.plan.id, self.owner)
        by_user = {item.user_id: item for item in balances.balances}
        self.assertEqual(balances.total_expenses, Decimal('1000.00'))
        self.assertEqual(by_user[self.owner.id].total_paid, Decimal('600.00'))
        self.assertEqual(by_user[self.owner.id].total_owed, Decimal('500.00'))
        self.assertEqual(by_user[self.owner.id].net_balance, Decimal('100.00'))
        self.assertEqual(by_user[self.member.id].total_paid, Decimal('400.00'))
        self.assertEqual(by_user[self.member.id].total_owed, Decimal('500.00'))
        self.assertEqual(by_user[self.member.id].net_balance, Decimal('-100.00'))
        self.assertEqual(len(balances.settlement_suggestions), 1)
        self.assertEqual(balances.settlement_suggestions[0].amount, Decimal('100.00'))

    def test_multiple_payment_contributions_must_equal_expense_amount(self):
        with self.assertRaises(ValidationError):
            self.budget_service.add_expense(
                self.plan.id,
                self.owner,
                amount='600.00',
                category='Food',
                payments=[
                    {'user_id': str(self.owner.id), 'amount': '500.00'},
                    {'user_id': str(self.member.id), 'amount': '50.00'},
                ],
            )

    def test_expense_api_returns_multiple_payment_contributions(self):
        self.client.force_authenticate(self.owner)
        response = self.client.post(
            reverse('plan-expenses', kwargs={'plan_id': self.plan.id}),
            {
                'amount': '600.00',
                'category': 'Food',
                'participants': [
                    {'user_id': str(self.owner.id)},
                    {'user_id': str(self.member.id)},
                ],
                'payments': [
                    {'user_id': str(self.owner.id), 'amount': '500.00'},
                    {'user_id': str(self.member.id), 'amount': '100.00'},
                ],
            },
            format='json',
        )

        self.assertEqual(response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(len(response.data['expense']['payments']), 2)
        self.assertEqual(
            sum(Decimal(item['amount']) for item in response.data['expense']['payments']),
            Decimal('600.00'),
        )

    def test_percentage_and_exact_splits_are_validated(self):
        percentage_result = self.budget_service.add_expense(
            self.plan.id,
            self.owner,
            amount='1000000',
            category='Hotel',
            paid_by_user_id=self.owner.id,
            split_strategy='percentage',
            participants=[
                {'user_id': str(self.owner.id), 'percentage': '25'},
                {'user_id': str(self.member.id), 'percentage': '75'},
            ],
        )
        participant_amounts = {
            participant.user_id: participant.owed_amount
            for participant in percentage_result.expense.participants
        }
        self.assertEqual(participant_amounts[self.owner.id], Decimal('250000.00'))
        self.assertEqual(participant_amounts[self.member.id], Decimal('750000.00'))

        exact_result = self.budget_service.add_expense(
            self.plan.id,
            self.member,
            amount='300000',
            category='Tickets',
            paid_by_user_id=self.member.id,
            split_strategy='exact',
            participants=[
                {'user_id': str(self.owner.id), 'amount': '100000'},
                {'user_id': str(self.member.id), 'amount': '200000'},
            ],
        )
        exact_amounts = {
            participant.user_id: participant.owed_amount
            for participant in exact_result.expense.participants
        }
        self.assertEqual(exact_amounts[self.owner.id], Decimal('100000.00'))
        self.assertEqual(exact_amounts[self.member.id], Decimal('200000.00'))

    def test_settlement_reduces_debt_and_is_audited(self):
        self.budget_service.add_expense(
            self.plan.id,
            self.owner,
            amount='1200000',
            category='Food',
            paid_by_user_id=self.owner.id,
            split_strategy='equal',
            participants=[
                {'user_id': str(self.owner.id)},
                {'user_id': str(self.member.id)},
            ],
        )

        settlement = self.budget_service.create_settlement(
            plan_id=self.plan.id,
            actor=self.member,
            from_user_id=self.member.id,
            to_user_id=self.owner.id,
            amount='600000',
            currency='VND',
        )

        self.assertEqual(settlement.status, 'pending')
        self.assertEqual(Settlement.objects.count(), 1)
        pending_balances = self.budget_service.get_balances(self.plan.id, self.owner)
        self.assertEqual(len(pending_balances.settlement_suggestions), 1)

        settlement = self.budget_service.respond_to_settlement(
            settlement.id,
            self.owner,
            action='complete',
        )
        self.assertEqual(settlement.status, 'completed')
        balances = self.budget_service.get_balances(self.plan.id, self.owner)
        by_user = {item.user_id: item for item in balances.balances}
        self.assertEqual(by_user[self.owner.id].net_balance, Decimal('0.00'))
        self.assertEqual(by_user[self.member.id].net_balance, Decimal('0.00'))
        self.assertEqual(len(balances.settlement_suggestions), 0)
        self.assertTrue(
            AuditLog.objects.filter(
                action=AuditAction.SETTLEMENT_COMPLETED.value,
                resource_id=self.plan.id,
            ).exists()
        )

    def test_settlement_can_be_rejected_without_changing_balances(self):
        self.budget_service.add_expense(
            self.plan.id,
            self.owner,
            amount='200.00',
            category='Food',
            participants=[
                {'user_id': str(self.owner.id)},
                {'user_id': str(self.member.id)},
            ],
        )
        settlement = self.budget_service.create_settlement(
            plan_id=self.plan.id,
            actor=self.member,
            from_user_id=self.member.id,
            to_user_id=self.owner.id,
            amount='100.00',
        )
        rejected = self.budget_service.respond_to_settlement(
            settlement.id,
            self.owner,
            action='reject',
            rejection_reason='Payment not received',
        )
        self.assertEqual(rejected.status, 'rejected')
        self.assertEqual(rejected.rejection_reason, 'Payment not received')
        balances = self.budget_service.get_balances(self.plan.id, self.owner)
        self.assertEqual(len(balances.settlement_suggestions), 1)

        with self.assertRaises(ValidationError):
            self.budget_service.respond_to_settlement(
                settlement.id,
                self.owner,
                action='complete',
            )

    def test_pending_settlements_cannot_exceed_current_debt(self):
        self.budget_service.add_expense(
            self.plan.id,
            self.owner,
            amount='200.00',
            category='Food',
            participants=[
                {'user_id': str(self.owner.id)},
                {'user_id': str(self.member.id)},
            ],
        )
        self.budget_service.create_settlement(
            plan_id=self.plan.id,
            actor=self.member,
            from_user_id=self.member.id,
            to_user_id=self.owner.id,
            amount='80.00',
        )

        with self.assertRaises(ValidationError):
            self.budget_service.create_settlement(
                plan_id=self.plan.id,
                actor=self.member,
                from_user_id=self.member.id,
                to_user_id=self.owner.id,
                amount='30.00',
            )

    def test_corrective_entry_replaces_effective_expense_without_mutating_original(self):
        original = self.budget_service.add_expense(
            self.plan.id,
            self.owner,
            amount='200.00',
            category='Food',
            receipt='image/upload/planpal/expenses/receipts/original-proof',
            participants=[
                {'user_id': str(self.owner.id)},
                {'user_id': str(self.member.id)},
            ],
        ).expense
        corrected = self.budget_service.correct_expense(
            self.plan.id,
            original.id,
            self.owner,
            amount='300.00',
            category='Restaurant',
            description='Corrected receipt total',
            reason='Receipt total was entered incorrectly',
        )
        original_row = Expense.objects.get(id=original.id)
        corrected_row = Expense.objects.get(id=corrected.expense.id)
        self.assertEqual(original_row.amount, Decimal('200.00'))
        self.assertEqual(str(corrected_row.receipt), str(original_row.receipt))
        self.assertEqual(corrected.expense.entry_type, 'correction')
        self.assertEqual(corrected.expense.corrects_expense_id, original.id)
        self.assertEqual(corrected.summary.total_spent, Decimal('300.00'))
        self.assertEqual(corrected.summary.expense_count, 1)
        balances = self.budget_service.get_balances(self.plan.id, self.owner)
        by_user = {item.user_id: item for item in balances.balances}
        self.assertEqual(balances.total_expenses, Decimal('300.00'))
        self.assertEqual(by_user[self.owner.id].net_balance, Decimal('150.00'))
        self.assertEqual(by_user[self.member.id].net_balance, Decimal('-150.00'))

    def test_expense_correction_can_change_payer_and_payment_contributions(self):
        original = self.budget_service.add_expense(
            self.plan.id,
            self.owner,
            amount='100.00',
            category='Food',
            participants=[
                {'user_id': str(self.owner.id)},
                {'user_id': str(self.member.id)},
            ],
        ).expense
        self.client.force_authenticate(self.owner)
        url = reverse(
            'plan-expense-corrections',
            kwargs={'plan_id': self.plan.id, 'expense_id': original.id},
        )
        reassigned = self.client.post(url, {
            'amount': '100.00',
            'category': 'Food',
            'reason': 'Member paid instead',
            'paid_by_user_id': str(self.member.id),
        }, format='json')
        self.assertEqual(reassigned.status_code, status.HTTP_201_CREATED)
        reassigned_id = reassigned.data['expense']['id']
        self.assertEqual(reassigned.data['expense']['paid_by_user_id'], self.member.id)
        self.assertEqual(Expense.objects.get(id=original.id).paid_by_user_id, self.owner.id)
        balances = self.budget_service.get_balances(self.plan.id, self.owner)
        by_user = {item.user_id: item for item in balances.balances}
        self.assertEqual(by_user[self.owner.id].net_balance, Decimal('-50.00'))
        self.assertEqual(by_user[self.member.id].net_balance, Decimal('50.00'))

        shared = self.client.post(reverse(
            'plan-expense-corrections',
            kwargs={'plan_id': self.plan.id, 'expense_id': reassigned_id},
        ), {
            'amount': '100.00',
            'category': 'Food',
            'reason': 'Both contributed',
            'payments': [
                {'user_id': str(self.owner.id), 'amount': '30.00'},
                {'user_id': str(self.member.id), 'amount': '70.00'},
            ],
        }, format='json')
        self.assertEqual(shared.status_code, status.HTTP_201_CREATED)
        self.assertEqual(shared.data['expense']['paid_by_user_id'], self.member.id)
        self.assertEqual(len(shared.data['expense']['payments']), 2)
        balances = self.budget_service.get_balances(self.plan.id, self.owner)
        by_user = {item.user_id: item for item in balances.balances}
        self.assertEqual(balances.total_expenses, Decimal('100.00'))
        self.assertEqual(by_user[self.owner.id].net_balance, Decimal('-20.00'))
        self.assertEqual(by_user[self.member.id].net_balance, Decimal('20.00'))

    def test_expense_correction_rejects_non_member_payer(self):
        original = self.budget_service.add_expense(
            self.plan.id, self.owner, amount='100.00', category='Food',
        ).expense
        self.client.force_authenticate(self.owner)
        response = self.client.post(reverse(
            'plan-expense-corrections',
            kwargs={'plan_id': self.plan.id, 'expense_id': original.id},
        ), {
            'amount': '100.00',
            'category': 'Food',
            'reason': 'Invalid payer',
            'paid_by_user_id': str(self.outsider.id),
        }, format='json')
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertEqual(Expense.objects.count(), 1)

    def test_expense_and_settlement_inherit_budget_currency(self):
        self.client.force_authenticate(self.owner)
        budget_url = reverse('plan-budget', kwargs={'plan_id': self.plan.id})
        expense_url = reverse('plan-expenses', kwargs={'plan_id': self.plan.id})
        self.assertEqual(self.client.post(
            budget_url, {'total_budget': '1000.00', 'currency': 'USD'}, format='json'
        ).status_code, status.HTTP_200_OK)
        expense = self.client.post(expense_url, {
            'amount': '100.00',
            'category': 'Food',
            'participants': [
                {'user_id': str(self.owner.id)},
                {'user_id': str(self.member.id)},
            ],
        }, format='json')
        self.assertEqual(expense.status_code, status.HTTP_201_CREATED)
        self.assertEqual(Expense.objects.get().currency, 'USD')
        self.assertEqual(self.client.post(expense_url, {
            'amount': '10.00', 'category': 'Food', 'currency': 'VND',
        }, format='json').status_code, status.HTTP_400_BAD_REQUEST)

        self.client.force_authenticate(self.member)
        settlement_url = reverse('settlements')
        settlement = self.client.post(settlement_url, {
            'plan_id': str(self.plan.id),
            'from_user_id': str(self.member.id),
            'to_user_id': str(self.owner.id),
            'amount': '50.00',
        }, format='json')
        self.assertEqual(settlement.status_code, status.HTTP_201_CREATED)
        self.assertEqual(Settlement.objects.get().currency, 'USD')
        self.assertEqual(self.client.post(settlement_url, {
            'plan_id': str(self.plan.id),
            'from_user_id': str(self.member.id),
            'to_user_id': str(self.owner.id),
            'amount': '10.00',
            'currency': 'VND',
        }, format='json').status_code, status.HTTP_400_BAD_REQUEST)

        self.client.force_authenticate(self.owner)
        self.assertEqual(self.client.post(
            budget_url, {'total_budget': '1200.00'}, format='json'
        ).status_code, status.HTTP_200_OK)
        self.assertEqual(Budget.objects.get(plan=self.plan).currency, 'USD')
        self.assertEqual(self.client.post(
            budget_url, {'total_budget': '1200.00', 'currency': 'VND'}, format='json'
        ).status_code, status.HTTP_400_BAD_REQUEST)

    def test_recurring_expense_generation_is_advanced_after_one_occurrence(self):
        next_run = timezone.now() + timedelta(days=1)
        self.budget_service.add_expense(
            self.plan.id,
            self.owner,
            amount='120.00',
            category='Transport',
            participants=[
                {'user_id': str(self.owner.id)},
                {'user_id': str(self.member.id)},
            ],
            recurrence={
                'frequency': 'weekly',
                'interval': 1,
                'next_run_at': next_run,
            },
        )
        rule = RecurringExpense.objects.get()
        outcome = self.budget_service.generate_due_recurring_expenses(
            now=next_run + timedelta(minutes=1),
        )
        self.assertEqual(outcome['created'], 1)
        self.assertEqual(Expense.objects.filter(recurrence=rule).count(), 2)
        repeated_outcome = self.budget_service.generate_due_recurring_expenses(
            now=next_run + timedelta(minutes=1),
        )
        self.assertEqual(repeated_outcome['created'], 0)
        self.assertEqual(Expense.objects.filter(recurrence=rule).count(), 2)
        rule.refresh_from_db()
        self.assertEqual(rule.last_run_at, next_run)

    def test_recurring_expense_creator_can_pause_and_outsider_cannot(self):
        self.budget_service.add_expense(
            self.plan.id,
            self.member,
            amount='120.00',
            category='Transport',
            participants=[
                {'user_id': str(self.owner.id)},
                {'user_id': str(self.member.id)},
            ],
            recurrence={
                'frequency': 'monthly',
                'interval': 1,
                'next_run_at': timezone.now() + timedelta(days=30),
            },
        )
        rule = RecurringExpense.objects.get()

        paused = self.budget_service.set_recurring_expense_active(
            self.plan.id,
            rule.id,
            self.member,
            is_active=False,
        )
        self.assertFalse(paused.is_active)

        with self.assertRaises(PermissionDenied):
            self.budget_service.set_recurring_expense_active(
                self.plan.id,
                rule.id,
                self.outsider,
                is_active=True,
            )

        self.client.force_authenticate(self.owner)
        response = self.client.patch(
            reverse(
                'plan-recurring-expense-status',
                kwargs={'plan_id': self.plan.id, 'recurring_id': rule.id},
            ),
            {'is_active': True},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['is_active'])

    def test_finance_insights_returns_categories_and_over_budget_forecast(self):
        self.budget_service.create_or_update_budget(
            self.plan.id,
            self.owner,
            total_budget='100.00',
        )
        self.budget_service.add_expense(
            self.plan.id,
            self.owner,
            amount='80.00',
            category='Food',
        )
        insights = self.budget_service.get_finance_insights(self.plan.id, self.owner)
        self.assertEqual(insights.categories[0].category, 'Food')
        self.assertEqual(insights.categories[0].percentage, 100.0)
        self.assertGreaterEqual(insights.forecast.projected_total, Decimal('80.00'))

    def test_settlement_api_enforces_pending_then_receiver_confirmation(self):
        self.budget_service.add_expense(
            self.plan.id,
            self.owner,
            amount='200.00',
            category='Food',
            participants=[
                {'user_id': str(self.owner.id)},
                {'user_id': str(self.member.id)},
            ],
        )
        self.client.force_authenticate(self.member)
        create_response = self.client.post(
            reverse('settlements'),
            {
                'plan_id': str(self.plan.id),
                'from_user_id': str(self.member.id),
                'to_user_id': str(self.owner.id),
                'amount': '100.00',
                'payment_note': 'Bank transfer 123',
            },
            format='json',
        )
        self.assertEqual(create_response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(create_response.data['status'], 'pending')

        self.client.force_authenticate(self.owner)
        complete_response = self.client.post(
            reverse(
                'settlement-action',
                kwargs={
                    'settlement_id': create_response.data['id'],
                    'action': 'complete',
                },
            ),
            {},
            format='json',
        )
        self.assertEqual(complete_response.status_code, status.HTTP_200_OK)
        self.assertEqual(complete_response.data['status'], 'completed')

    def test_expense_correction_and_finance_insights_api_contract(self):
        original = self.budget_service.add_expense(
            self.plan.id,
            self.owner,
            amount='100.00',
            category='Food',
        ).expense
        self.client.force_authenticate(self.owner)
        correction_response = self.client.post(
            reverse(
                'plan-expense-corrections',
                kwargs={'plan_id': self.plan.id, 'expense_id': original.id},
            ),
            {
                'amount': '150.00',
                'category': 'Restaurant',
                'description': 'Correct total',
                'reason': 'Receipt was read incorrectly',
                'split_strategy': 'exact',
                'participants': [
                    {'user_id': str(self.owner.id), 'amount': '50.00'},
                    {'user_id': str(self.member.id), 'amount': '100.00'},
                ],
            },
            format='json',
        )
        self.assertEqual(correction_response.status_code, status.HTTP_201_CREATED)
        self.assertEqual(correction_response.data['expense']['entry_type'], 'correction')
        self.assertEqual(correction_response.data['expense']['split_strategy'], 'exact')
        self.assertEqual(len(correction_response.data['expense']['participants']), 2)
        self.assertEqual(correction_response.data['summary']['total_spent'], Decimal('150.00'))

        expenses_response = self.client.get(
            reverse('plan-expenses', kwargs={'plan_id': self.plan.id}),
        )
        self.assertEqual(expenses_response.data['count'], 1)
        self.assertEqual(expenses_response.data['results'][0]['id'], correction_response.data['expense']['id'])

        insights_response = self.client.get(
            reverse('plan-finance-insights', kwargs={'plan_id': self.plan.id}),
        )
        self.assertEqual(insights_response.status_code, status.HTTP_200_OK)
        self.assertEqual(insights_response.data['categories'][0]['category'], 'Restaurant')

    def test_expense_delete_recalculates_ledger_and_keeps_audit_record(self):
        expense = self.budget_service.add_expense(
            self.plan.id,
            self.member,
            amount='125.00',
            category='Transport',
        ).expense
        self.client.force_authenticate(self.member)

        response = self.client.delete(
            reverse(
                'plan-expense-detail',
                kwargs={'plan_id': self.plan.id, 'expense_id': expense.id},
            ),
        )

        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        self.assertEqual(
            self.budget_service.get_budget_summary(self.plan.id, self.owner).total_spent,
            Decimal('0.00'),
        )
        self.assertIsNotNone(Expense.objects.get(id=expense.id).deleted_at)
        self.assertTrue(
            AuditLog.objects.filter(
                action=AuditAction.DELETE_EXPENSE.value,
                resource_id=self.plan.id,
            ).exists()
        )

    def test_outsider_cannot_read_settlements_or_finance_insights(self):
        self.client.force_authenticate(self.outsider)
        settlements_response = self.client.get(
            reverse('settlements'),
            {'plan_id': str(self.plan.id)},
        )
        insights_response = self.client.get(
            reverse('plan-finance-insights', kwargs={'plan_id': self.plan.id}),
        )
        self.assertEqual(settlements_response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertEqual(insights_response.status_code, status.HTTP_403_FORBIDDEN)

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
        self.assertEqual(outcome['notifications_sent'], 3)
        self.assertEqual(
            Notification.objects.filter(
                user=self.owner,
                type=NotificationType.EXPENSE_ADDED.value,
            ).count(),
            1,
        )
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

    def test_plan_audit_feed_includes_budget_actions_and_legacy_related_logs(self):
        self.budget_service.create_or_update_budget(
            self.plan.id,
            self.owner,
            total_budget='1000000',
            currency='VND',
        )
        self.budget_service.add_expense(
            self.plan.id,
            self.member,
            amount='250000',
            category='Food',
            description='Audit expense',
        )
        AuditLog.objects.create(
            user=self.owner,
            action=AuditAction.UPDATE_BUDGET.value,
            resource_type=AuditResourceType.BUDGET.value,
            resource_id=uuid4(),
            metadata={
                'plan_id': str(self.plan.id),
                'plan_title': self.plan.title,
                'total_budget': '1500000.00',
            },
        )
        AuditLog.objects.create(
            user=self.member,
            action=AuditAction.CREATE_EXPENSE.value,
            resource_type=AuditResourceType.EXPENSE.value,
            resource_id=uuid4(),
            metadata={
                'plan_id': str(self.plan.id),
                'plan_title': self.plan.title,
                'amount': '125000.00',
                'category': 'Transport',
            },
        )

        self.client.force_authenticate(self.owner)
        response = self.client.get(
            reverse(
                'audit-log-resource',
                kwargs={
                    'resource_type': AuditResourceType.PLAN.value,
                    'resource_id': self.plan.id,
                },
            ),
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        actions = [item['action'] for item in response.data['results']]
        self.assertIn(AuditAction.UPDATE_BUDGET.value, actions)
        self.assertIn(AuditAction.CREATE_EXPENSE.value, actions)
