from datetime import timezone as datetime_timezone
from urllib.parse import quote

from planpals.collaboration.domain.entities import (
    ALLOWED_REACTIONS,
    AvailabilityStatus,
    WorkItemStatus,
    WorkItemType,
)
from planpals.collaboration.domain.exceptions import (
    CollaborationConflict,
    CollaborationNotFound,
    CollaborationPermissionDenied,
)


class CollaborationService:
    def __init__(self, repository, audit_service=None, realtime_publisher=None):
        self.repository = repository
        self.audit_service = audit_service
        self.realtime = realtime_publisher

    def list_polls(self, group_id, user_id):
        self._require_group_member(group_id, user_id)
        return self.repository.list_polls(group_id)

    def create_poll(self, group_id, user_id, title, closes_at, options):
        if not self.repository.can_manage_group_planning(group_id, user_id):
            raise CollaborationPermissionDenied(
                'Only group admins and plan creators can create availability polls.'
            )
        normalized_title = (title or '').strip()
        if not normalized_title:
            raise CollaborationConflict('Poll title is required.', 'invalid_title')
        if not 2 <= len(options) <= 20:
            raise CollaborationConflict(
                'A poll must contain between 2 and 20 time options.', 'invalid_options'
            )
        if closes_at and closes_at <= self.repository.now():
            raise CollaborationConflict('Poll closing time must be in the future.', 'invalid_closing_time')
        unique_ranges = {(option['start_at'], option['end_at']) for option in options}
        if len(unique_ranges) != len(options):
            raise CollaborationConflict('Time options must be unique.', 'duplicate_options')
        for option in options:
            if option['end_at'] <= option['start_at']:
                raise CollaborationConflict(
                    'Every option must end after it starts.', 'invalid_time_range'
                )
        poll = self.repository.create_poll(
            group_id, user_id, normalized_title, closes_at, options
        )
        self._audit(user_id, 'CREATE_AVAILABILITY_POLL', 'group', group_id, {
            'poll_id': str(poll.id), 'title': poll.title,
        })
        self._publish_group(group_id, 'availability.poll_created', {
            'poll_id': str(poll.id), 'title': poll.title,
        })
        return poll

    def vote(self, poll_id, option_id, user_id, status):
        if status not in AvailabilityStatus.values():
            raise CollaborationConflict('Invalid availability status.', 'invalid_status')
        poll = next((item for item in self._all_polls_for_option(option_id)
                     if str(item.id) == str(poll_id)), None)
        if poll is None:
            raise CollaborationNotFound('Availability poll was not found.')
        self._require_group_member(poll.group_id, user_id)
        vote, error = self.repository.cast_vote(poll_id, option_id, user_id, status)
        if error == 'poll_closed':
            raise CollaborationConflict('This poll is already closed.', 'poll_closed')
        if error:
            raise CollaborationNotFound('Poll option was not found.')
        self._publish_group(poll.group_id, 'availability.vote_updated', {
            'poll_id': str(poll_id), 'option_id': str(option_id),
            'user_id': str(user_id), 'status': status,
        })
        return vote

    def _all_polls_for_option(self, option_id):
        # The repository stays the only layer aware of persistence; use the
        # option's group through the dedicated lookup added by the adapter.
        poll = self.repository.get_poll_for_option(option_id)
        return [poll] if poll else []

    def list_work_items(self, plan_id, user_id):
        self._require_plan_access(plan_id, user_id)
        return self.repository.list_work_items(plan_id)

    def create_work_item(self, plan_id, user_id, data):
        if not self.repository.can_manage_plan(plan_id, user_id):
            raise CollaborationPermissionDenied('You cannot create work items for this plan.')
        normalized = self._validate_work_item(plan_id, data)
        item = self.repository.create_work_item(plan_id, user_id, normalized)
        self._audit(user_id, 'CREATE_WORK_ITEM', 'plan', plan_id, {
            'work_item_id': str(item.id), 'title': item.title,
            'item_type': item.item_type,
        })
        self._publish_plan(plan_id, 'collaboration.work_item_created', {
            'work_item_id': str(item.id), 'title': item.title,
        })
        if item.assignee_id and item.assignee_id != user_id and self.realtime:
            self.realtime.notify_user(item.assignee_id, {
                'notification_title': 'New assignment',
                'notification_message': f'You were assigned: {item.title}',
                'plan_id': str(plan_id),
                'work_item_id': str(item.id),
                'work_item_title': item.title,
                'change_type': 'assignment',
            })
        return item

    def update_work_item(self, item_id, user_id, data):
        item = self.repository.get_work_item(item_id)
        if not item:
            raise CollaborationNotFound('Work item was not found.')
        can_manage = self.repository.can_manage_plan(item.plan_id, user_id)
        only_status = set(data).issubset({'status'})
        if not can_manage and not (item.assignee_id == user_id and only_status):
            raise CollaborationPermissionDenied('You cannot update this work item.')
        normalized = self._validate_work_item(item.plan_id, data, partial=True)
        status = normalized.get('status')
        if status:
            normalized['completed_at'] = self.repository.now() if status == 'done' else None
        updated = self.repository.update_work_item(item_id, normalized)
        self._audit(user_id, 'UPDATE_WORK_ITEM', 'plan', item.plan_id, {
            'work_item_id': str(item.id), 'title': item.title,
            'changed_fields': sorted(data.keys()),
        })
        self._publish_plan(item.plan_id, 'collaboration.work_item_updated', {
            'work_item_id': str(item.id), 'status': updated.status,
        })
        return updated

    def delete_work_item(self, item_id, user_id):
        item = self.repository.get_work_item(item_id)
        if not item:
            raise CollaborationNotFound('Work item was not found.')
        if not self.repository.can_manage_plan(item.plan_id, user_id):
            raise CollaborationPermissionDenied('You cannot delete this work item.')
        self.repository.delete_work_item(item_id)
        self._publish_plan(item.plan_id, 'collaboration.work_item_deleted', {
            'work_item_id': str(item.id),
        })

    def list_comments(self, plan_id, user_id, activity_id=None):
        self._require_plan_access(plan_id, user_id)
        return self.repository.list_comments(plan_id, activity_id)

    def create_comment(self, plan_id, user_id, data):
        self._require_plan_access(plan_id, user_id)
        body = (data.get('body') or '').strip()
        if not body:
            raise CollaborationConflict('Comment cannot be empty.', 'empty_comment')
        if len(body) > 4000:
            raise CollaborationConflict('Comment is too long.', 'comment_too_long')
        self._validate_comment_links(plan_id, data)
        mention_ids = list(dict.fromkeys(data.get('mention_user_ids', [])))
        for mentioned_id in mention_ids:
            if not self.repository.is_plan_member(plan_id, mentioned_id):
                raise CollaborationConflict(
                    'Mentioned users must belong to the plan.', 'invalid_mention'
                )
        payload = {
            'body': body,
            'activity_id': data.get('activity_id'),
            'parent_id': data.get('parent_id'),
            'mention_user_ids': mention_ids,
        }
        comment = self.repository.create_comment(plan_id, user_id, payload)
        self._audit(user_id, 'CREATE_COMMENT', 'plan', plan_id, {
            'comment_id': str(comment.id),
            'activity_id': str(comment.activity_id) if comment.activity_id else None,
        })
        self._publish_plan(plan_id, 'collaboration.comment_created', {
            'comment_id': str(comment.id), 'author_id': str(user_id),
        })
        if self.realtime:
            for mentioned_id in mention_ids:
                if mentioned_id != user_id:
                    self.realtime.notify_user(mentioned_id, {
                        'notification_title': 'You were mentioned',
                        'notification_message': body[:160],
                        'plan_id': str(plan_id),
                        'comment_id': str(comment.id),
                        'comment_excerpt': body[:160],
                        'change_type': 'mention',
                    })
        return comment

    def update_comment(self, comment_id, user_id, body):
        comment = self._require_comment(comment_id)
        if comment.author_id != user_id:
            raise CollaborationPermissionDenied('Only the author can edit this comment.')
        normalized = (body or '').strip()
        if not normalized:
            raise CollaborationConflict('Comment cannot be empty.', 'empty_comment')
        updated = self.repository.update_comment(comment_id, normalized)
        self._publish_plan(comment.plan_id, 'collaboration.comment_updated', {
            'comment_id': str(comment.id),
        })
        return updated

    def delete_comment(self, comment_id, user_id):
        comment = self._require_comment(comment_id)
        if comment.author_id != user_id and not self.repository.can_manage_plan(
            comment.plan_id, user_id
        ):
            raise CollaborationPermissionDenied('You cannot delete this comment.')
        self.repository.delete_comment(comment_id)
        self._publish_plan(comment.plan_id, 'collaboration.comment_deleted', {
            'comment_id': str(comment.id),
        })

    def react(self, comment_id, user_id, reaction):
        comment = self._require_comment(comment_id)
        self._require_plan_access(comment.plan_id, user_id)
        if reaction is not None and reaction not in ALLOWED_REACTIONS:
            raise CollaborationConflict('Invalid reaction.', 'invalid_reaction')
        self.repository.set_reaction(comment_id, user_id, reaction)
        self._publish_plan(comment.plan_id, 'collaboration.reaction_updated', {
            'comment_id': str(comment.id), 'user_id': str(user_id),
            'reaction': reaction,
        })

    def toggle_pin(self, comment_id, user_id):
        comment = self._require_comment(comment_id)
        if not self.repository.can_manage_plan(comment.plan_id, user_id):
            raise CollaborationPermissionDenied('You cannot pin content in this plan.')
        updated = self.repository.toggle_pin(comment_id, user_id)
        self._audit(user_id, 'PIN_COMMENT' if updated.is_pinned else 'UNPIN_COMMENT',
                    'plan', comment.plan_id, {'comment_id': str(comment.id)})
        self._publish_plan(comment.plan_id, 'collaboration.comment_pinned', {
            'comment_id': str(comment.id), 'is_pinned': updated.is_pinned,
        })
        return updated

    def clone_plan(self, plan_id, user_id, data):
        source = self.repository.get_plan(plan_id)
        if not source:
            raise CollaborationNotFound('Plan was not found.')
        if not self.repository.can_access_plan(plan_id, user_id):
            raise CollaborationPermissionDenied('You cannot clone this plan.')
        if source.group_id and not self.repository.can_manage_group_planning(
            source.group_id, user_id
        ):
            raise CollaborationPermissionDenied(
                'Only a group admin or plan creator can clone this group plan.'
            )
        if not data.get('start_date'):
            raise CollaborationConflict('A new start date is required.', 'start_date_required')
        clone = self.repository.clone_plan(plan_id, user_id, data)
        self._audit(user_id, 'CLONE_PLAN', 'plan', clone.id, {
            'source_plan_id': str(plan_id), 'title': clone.title,
            'is_template': clone.is_template,
        })
        self._publish_plan(clone.id, 'plan.cloned', {
            'source_plan_id': str(plan_id), 'plan_id': str(clone.id),
        })
        return clone

    def export_ics(self, plan_id, user_id):
        self._require_plan_access(plan_id, user_id)
        plan = self.repository.get_plan_for_export(plan_id)
        lines = ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//PlanPal//Plan Calendar//EN',
                 'CALSCALE:GREGORIAN', 'METHOD:PUBLISH']
        for activity in plan.activities.all():
            lines.extend([
                'BEGIN:VEVENT',
                f'UID:{activity.id}@planpal',
                f'DTSTAMP:{self._ics_datetime(activity.updated_at)}',
                f'DTSTART:{self._ics_datetime(activity.start_time)}',
                f'DTEND:{self._ics_datetime(activity.end_time)}',
                f'SUMMARY:{self._ics_escape(activity.title)}',
                f'DESCRIPTION:{self._ics_escape(activity.description or activity.notes)}',
                f'LOCATION:{self._ics_escape(activity.location_address or activity.location_name)}',
                'END:VEVENT',
            ])
        lines.append('END:VCALENDAR')
        return '\r\n'.join(lines) + '\r\n'

    def google_calendar_links(self, plan_id, user_id):
        self._require_plan_access(plan_id, user_id)
        plan = self.repository.get_plan_for_export(plan_id)
        result = []
        for activity in plan.activities.all():
            params = (
                f'action=TEMPLATE&text={quote(activity.title)}'
                f'&dates={self._ics_datetime(activity.start_time)}/{self._ics_datetime(activity.end_time)}'
                f'&details={quote(activity.description or activity.notes)}'
                f'&location={quote(activity.location_address or activity.location_name)}'
            )
            result.append({
                'activity_id': str(activity.id),
                'title': activity.title,
                'url': f'https://calendar.google.com/calendar/render?{params}',
            })
        return result

    def _validate_work_item(self, plan_id, data, partial=False):
        payload = dict(data)
        if not partial or 'title' in payload:
            payload['title'] = (payload.get('title') or '').strip()
            if not payload['title']:
                raise CollaborationConflict('Work item title is required.', 'invalid_title')
        if 'item_type' in payload and payload['item_type'] not in WorkItemType.values():
            raise CollaborationConflict('Invalid work item type.', 'invalid_item_type')
        if 'status' in payload and payload['status'] not in WorkItemStatus.values():
            raise CollaborationConflict('Invalid work item status.', 'invalid_status')
        assignee_id = payload.get('assignee_id')
        if assignee_id and not self.repository.is_plan_member(plan_id, assignee_id):
            raise CollaborationConflict('Assignee must belong to this plan.', 'invalid_assignee')
        activity_id = payload.get('activity_id')
        if activity_id and not self.repository.activity_belongs_to_plan(activity_id, plan_id):
            raise CollaborationConflict('Activity does not belong to this plan.', 'invalid_activity')
        return payload

    def _validate_comment_links(self, plan_id, data):
        activity_id = data.get('activity_id')
        if activity_id and not self.repository.activity_belongs_to_plan(activity_id, plan_id):
            raise CollaborationConflict('Activity does not belong to this plan.', 'invalid_activity')
        parent_id = data.get('parent_id')
        if parent_id:
            parent = self.repository.get_comment(parent_id)
            if not parent or parent.plan_id != plan_id:
                raise CollaborationConflict('Reply target is invalid.', 'invalid_parent')

    def _require_group_member(self, group_id, user_id):
        if not self.repository.get_group(group_id):
            raise CollaborationNotFound('Group was not found.')
        if not self.repository.is_group_member(group_id, user_id):
            raise CollaborationPermissionDenied('You are not a member of this group.')

    def _require_plan_access(self, plan_id, user_id):
        if not self.repository.get_plan(plan_id):
            raise CollaborationNotFound('Plan was not found.')
        if not self.repository.can_access_plan(plan_id, user_id):
            raise CollaborationPermissionDenied('You cannot access this plan.')

    def _require_comment(self, comment_id):
        comment = self.repository.get_comment(comment_id)
        if not comment:
            raise CollaborationNotFound('Comment was not found.')
        return comment

    def _audit(self, user_id, action, resource_type, resource_id, metadata):
        if self.audit_service:
            self.audit_service.log_action(user_id, action, resource_type, resource_id, metadata)

    def _publish_plan(self, plan_id, event_type, data):
        if self.realtime:
            self.realtime.publish_plan(plan_id, event_type, data)

    def _publish_group(self, group_id, event_type, data):
        if self.realtime:
            self.realtime.publish_group(group_id, event_type, data)

    @staticmethod
    def _ics_escape(value):
        return str(value or '').replace('\\', '\\\\').replace(';', '\\;').replace(',', '\\,').replace('\n', '\\n')

    @staticmethod
    def _ics_datetime(value):
        return value.astimezone(datetime_timezone.utc).strftime('%Y%m%dT%H%M%SZ')
