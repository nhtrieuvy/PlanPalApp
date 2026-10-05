from datetime import timedelta

from django.db import transaction
from django.db.models import Prefetch
from django.utils import timezone

from planpals.budgets.infrastructure.models import Budget
from planpals.collaboration.application.repositories import CollaborationRepository
from planpals.collaboration.infrastructure.models import (
    AvailabilityOption,
    AvailabilityPoll,
    AvailabilityVote,
    CommentMention,
    CommentReaction,
    PlanComment,
    PlanWorkItem,
)
from planpals.groups.infrastructure.models import Group, GroupMembership
from planpals.plans.infrastructure.models import Plan, PlanActivity


class DjangoCollaborationRepository(CollaborationRepository):
    def get_group(self, group_id):
        return Group.objects.filter(id=group_id).first()

    def is_group_member(self, group_id, user_id) -> bool:
        return GroupMembership.objects.filter(group_id=group_id, user_id=user_id).exists()

    def can_manage_group_planning(self, group_id, user_id) -> bool:
        return GroupMembership.objects.filter(
            group_id=group_id,
            user_id=user_id,
            role__in=[GroupMembership.ADMIN, GroupMembership.PLAN_CREATOR],
        ).exists()

    def list_polls(self, group_id):
        vote_qs = AvailabilityVote.objects.select_related('user').order_by('created_at')
        option_qs = AvailabilityOption.objects.prefetch_related(
            Prefetch('votes', queryset=vote_qs)
        )
        return AvailabilityPoll.objects.filter(group_id=group_id).select_related(
            'created_by'
        ).prefetch_related(Prefetch('options', queryset=option_qs))

    def get_poll_for_option(self, option_id):
        option = AvailabilityOption.objects.select_related('poll').filter(id=option_id).first()
        return option.poll if option else None

    @transaction.atomic
    def create_poll(self, group_id, user_id, title, closes_at, options):
        poll = AvailabilityPoll.objects.create(
            group_id=group_id,
            created_by_id=user_id,
            title=title,
            closes_at=closes_at,
        )
        AvailabilityOption.objects.bulk_create([
            AvailabilityOption(
                poll=poll,
                label=option.get('label', ''),
                start_at=option['start_at'],
                end_at=option['end_at'],
            )
            for option in options
        ])
        return self.list_polls(group_id).get(id=poll.id)

    @transaction.atomic
    def cast_vote(self, poll_id, option_id, user_id, vote_status):
        poll = AvailabilityPoll.objects.select_for_update().filter(id=poll_id).first()
        if poll is None:
            return None, 'poll_not_found'
        if poll.is_closed or (poll.closes_at and poll.closes_at <= timezone.now()):
            return None, 'poll_closed'
        option = AvailabilityOption.objects.filter(id=option_id, poll=poll).first()
        if option is None:
            return None, 'option_not_found'
        vote, _ = AvailabilityVote.objects.update_or_create(
            option=option,
            user_id=user_id,
            defaults={'status': vote_status},
        )
        return vote, None

    def get_plan(self, plan_id):
        return Plan.objects.select_related('creator', 'group').filter(id=plan_id).first()

    def can_access_plan(self, plan_id, user_id) -> bool:
        plan = self.get_plan(plan_id)
        if not plan:
            return False
        return plan.creator_id == user_id or bool(
            plan.group_id and self.is_group_member(plan.group_id, user_id)
        )

    def can_manage_plan(self, plan_id, user_id) -> bool:
        plan = self.get_plan(plan_id)
        if not plan:
            return False
        if plan.creator_id == user_id:
            return True
        return bool(
            plan.group_id and self.can_manage_group_planning(plan.group_id, user_id)
        )

    def is_plan_member(self, plan_id, user_id) -> bool:
        return self.can_access_plan(plan_id, user_id)

    def activity_belongs_to_plan(self, activity_id, plan_id) -> bool:
        return PlanActivity.objects.filter(id=activity_id, plan_id=plan_id).exists()

    def get_plan_for_export(self, plan_id):
        return Plan.objects.prefetch_related(
            Prefetch('activities', queryset=PlanActivity.objects.order_by('start_time'))
        ).get(id=plan_id)

    def now(self):
        return timezone.now()

    def list_work_items(self, plan_id):
        return PlanWorkItem.objects.filter(plan_id=plan_id).select_related(
            'assignee', 'created_by', 'activity'
        )

    def get_work_item(self, item_id):
        return PlanWorkItem.objects.select_related(
            'plan', 'assignee', 'created_by'
        ).filter(id=item_id).first()

    @transaction.atomic
    def create_work_item(self, plan_id, user_id, data):
        return PlanWorkItem.objects.create(
            plan_id=plan_id,
            created_by_id=user_id,
            **data,
        )

    @transaction.atomic
    def update_work_item(self, item_id, data):
        item = PlanWorkItem.objects.select_for_update().select_related(
            'plan', 'assignee'
        ).filter(id=item_id).first()
        if not item:
            return None
        for field, value in data.items():
            setattr(item, field, value)
        item.save()
        return item

    @transaction.atomic
    def delete_work_item(self, item_id) -> None:
        PlanWorkItem.objects.filter(id=item_id).delete()

    def list_comments(self, plan_id, activity_id=None):
        reactions = CommentReaction.objects.select_related('user').order_by('created_at')
        mentions = CommentMention.objects.select_related('user').order_by('created_at')
        queryset = PlanComment.objects.filter(plan_id=plan_id).select_related(
            'author', 'activity', 'pinned_by'
        ).prefetch_related(
            Prefetch('reactions', queryset=reactions),
            Prefetch('mentions', queryset=mentions),
        )
        if activity_id:
            queryset = queryset.filter(activity_id=activity_id)
        return queryset

    def get_comment(self, comment_id):
        return PlanComment.objects.select_related(
            'plan', 'author', 'activity', 'pinned_by'
        ).filter(id=comment_id).first()

    @transaction.atomic
    def create_comment(self, plan_id, user_id, data):
        mention_ids = data.pop('mention_user_ids', [])
        comment = PlanComment.objects.create(plan_id=plan_id, author_id=user_id, **data)
        CommentMention.objects.bulk_create([
            CommentMention(comment=comment, user_id=mentioned_id)
            for mentioned_id in mention_ids
        ], ignore_conflicts=True)
        return self.list_comments(plan_id).get(id=comment.id)

    @transaction.atomic
    def update_comment(self, comment_id, body):
        comment = PlanComment.objects.select_for_update().filter(id=comment_id).first()
        if comment:
            comment.body = body
            comment.save(update_fields=['body', 'updated_at'])
        return comment

    @transaction.atomic
    def delete_comment(self, comment_id) -> None:
        PlanComment.objects.filter(id=comment_id).delete()

    @transaction.atomic
    def set_reaction(self, comment_id, user_id, reaction):
        existing = CommentReaction.objects.select_for_update().filter(
            comment_id=comment_id, user_id=user_id
        ).first()
        if reaction is None:
            if existing:
                existing.delete()
            return None
        if existing:
            existing.reaction = reaction
            existing.save(update_fields=['reaction', 'updated_at'])
            return existing
        return CommentReaction.objects.create(
            comment_id=comment_id, user_id=user_id, reaction=reaction
        )

    @transaction.atomic
    def toggle_pin(self, comment_id, user_id):
        comment = PlanComment.objects.select_for_update().filter(id=comment_id).first()
        if not comment:
            return None
        comment.is_pinned = not comment.is_pinned
        comment.pinned_by_id = user_id if comment.is_pinned else None
        comment.pinned_at = timezone.now() if comment.is_pinned else None
        comment.save(update_fields=['is_pinned', 'pinned_by', 'pinned_at', 'updated_at'])
        return comment

    @transaction.atomic
    def clone_plan(self, source_plan_id, user_id, data):
        source = Plan.objects.select_for_update().prefetch_related('activities').get(
            id=source_plan_id
        )
        target_start = data['start_date']
        target_end = target_start + (source.end_date - source.start_date)
        as_template = bool(data.get('as_template', False))
        clone = Plan.objects.create(
            title=data.get('title') or f'{source.title} (copy)',
            description=source.description,
            creator_id=user_id,
            group_id=source.group_id,
            start_date=target_start,
            end_date=target_end,
            is_public=source.is_public,
            is_template=as_template,
            status='upcoming',
        )
        delta = target_start - source.start_date
        PlanActivity.objects.bulk_create([
            PlanActivity(
                plan=clone,
                title=item.title,
                description=item.description,
                activity_type=item.activity_type,
                start_time=item.start_time + delta,
                end_time=item.end_time + delta,
                location_name=item.location_name,
                location_address=item.location_address,
                latitude=item.latitude,
                longitude=item.longitude,
                goong_place_id=item.goong_place_id,
                estimated_cost=item.estimated_cost,
                notes=item.notes,
                order=item.order,
            )
            for item in source.activities.all()
        ])
        source_budget = Budget.objects.filter(plan=source).first()
        Budget.objects.create(
            plan=clone,
            total_budget=source_budget.total_budget if source_budget else 0,
            currency=source_budget.currency if source_budget else 'VND',
        )
        return clone
