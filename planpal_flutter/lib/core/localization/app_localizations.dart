import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_locale.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) {
    final localizations = Localizations.of<AppLocalizations>(
      context,
      AppLocalizations,
    );
    assert(
      localizations != null,
      'AppLocalizations is not available in context',
    );
    return localizations!;
  }

  static const Map<String, Map<String, String>> _translations = {
    'en': {
      'common.app_name': 'PlanPal',
      'common.retry': 'Retry',
      'common.refresh': 'Refresh',
      'common.cancel': 'Cancel',
      'common.save': 'Save',
      'common.close': 'Close',
      'common.confirm': 'Confirm',
      'common.search': 'Search',
      'common.error': 'Error',
      'common.delete': 'Delete',
      'common.edit': 'Edit',
      'common.other': 'Other',
      'common.unknown': 'Unknown',
      'common.loading_session': 'Starting your session...',
      'common.language': 'Language',
      'common.language_english': 'English',
      'common.language_vietnamese': 'Vietnamese',
      'common.not_logged_in': 'Not signed in',
      'common.all': 'All',
      'common.read': 'Read',
      'common.unread': 'Unread',
      'common.just_now': 'Just now',
      'common.minutes_ago': '{count} minutes ago',
      'common.hours_ago': '{count} hours ago',
      'common.days_ago': '{count} days ago',
      'common.view_all': 'View all',
      'common.apply': 'Apply',
      'common.add': 'Add',
      'common.quick_add': 'Quick add',
      'common.filter': 'Filter',
      'common.newest_first': 'Newest first',
      'common.oldest_first': 'Oldest first',
      'common.highest_amount': 'Highest amount',
      'common.lowest_amount': 'Lowest amount',
      'common.open': 'Open',
      'common.free': 'Free',
      'common.clear_filters': 'Clear filters',
      'common.from_date': 'From date',
      'common.to_date': 'To date',
      'common.yes': 'Yes',
      'common.no': 'No',
      'activity_collab.polling_fallback':
          'Realtime is unavailable. The schedule is syncing periodically.',
      'activity_collab.realtime_connecting': 'Connecting realtime updates...',
      'activity_collab.edited_by': '{user} edited: {fields}',
      'activity_collab.edited_fields': 'Updated fields: {fields}',
      'activity_collab.version_label': 'Version',
      'activity_collab.current_version': 'Current version: {version}',
      'activity_collab.save_changes': 'Save changes',
      'activity_collab.conflict_title': 'Activity conflict detected',
      'activity_collab.conflict_versions':
          'Your version: {client} | Server version: {server}',
      'activity_collab.conflict_fields': 'Conflicting fields: {fields}',
      'activity_collab.use_server': 'Load server version',
      'activity_collab.overwrite': 'Overwrite with my changes',
      'activity_collab.server_version_loaded':
          'The latest server version has been loaded into the form.',

      'home.notifications': 'Notifications',
      'home.conversations': 'Conversations',
      'home.groups': 'Groups',
      'home.plans': 'Plans',
      'home.analytics': 'Analytics',
      'home.profile': 'Profile',
      'home.greeting_morning': 'Good morning!',
      'home.greeting_afternoon': 'Good afternoon!',
      'home.greeting_evening': 'Good evening!',
      'home.ready_for_trip': 'Ready for the next adventure?',
      'home.quick_actions': 'Quick actions',
      'home.create_plan': 'Create plan',
      'home.join_group': 'Join group',
      'home.find_friends': 'Find friends',
      'home.map': 'Map',
      'home.recent_plans': 'Recent plans',
      'home.active_groups': 'Active groups',
      'home.no_plans_title': 'No plans yet',
      'home.no_plans_description': 'Create your first plan for the next trip.',
      'home.no_groups_title': 'No groups yet',
      'home.no_groups_description':
          'Join or create a group to coordinate shared plans.',
      'home.group_prefix': 'Group: {group}',
      'home.copyright': '© 2026 PlanPal',
      'home.language_sheet_title': 'Choose language',

      'auth.login_title': 'Sign in to PlanPal',
      'auth.username': 'Username',
      'auth.password': 'Password',
      'auth.enter_username': 'Enter your username',
      'auth.enter_password': 'Enter your password',
      'auth.login': 'Sign in',
      'auth.no_account': 'No account yet?',
      'auth.register_now': 'Create one',
      'auth.register_title': 'Create account',
      'auth.register_subtitle':
          'Join PlanPal to plan trips together with your friends.',
      'auth.add_photo': 'Add photo',
      'auth.email': 'Email',
      'auth.first_name': 'First name',
      'auth.last_name': 'Last name',
      'auth.phone_optional': 'Phone number (optional)',
      'auth.confirm_password': 'Confirm password',
      'auth.register': 'Register',
      'auth.registering': 'Registering...',
      'auth.have_account': 'Already have an account?',
      'auth.pick_image_error': 'Could not pick image: {error}',
      'auth.register_success': 'Registration completed successfully.',
      'auth.register_verify_email':
          'Account created. Please enter the 6-digit code sent to your email.',
      'auth.register_failed': 'Registration failed: {error}',
      'auth.verify_email_title': 'Verify your email',
      'auth.verify_email_subtitle':
          'Enter the 6-digit verification code sent to {email}.',
      'auth.verification_code': 'Verification code',
      'auth.verify_email_action': 'Verify email',
      'auth.verifying': 'Verifying...',
      'auth.resend_code': 'Resend code',
      'auth.resending_code': 'Resending...',
      'auth.back_to_login': 'Back to sign in',
      'auth.verify_email_success':
          'Email verified successfully. You can now sign in.',
      'auth.verify_email_failed':
          'The verification code is invalid or expired. Please try again.',
      'auth.verify_email_resend_success':
          'A new verification code has been sent.',
      'auth.verify_email_resend_failed':
          'Could not resend the verification code. Please try again.',
      'auth.verify_email_code_required': 'Please enter the 6-digit code',
      'auth.validation_username_required': 'Please enter a username',
      'auth.validation_username_short':
          'Username must have at least 2 characters',
      'auth.validation_email_required': 'Please enter your email',
      'auth.validation_email_invalid': 'Invalid email address',
      'auth.validation_first_name_required': 'Please enter your first name',
      'auth.validation_last_name_required': 'Please enter your last name',
      'auth.validation_phone_invalid': 'Invalid phone number',
      'auth.validation_phone_length':
          'Phone number must contain 9 to 15 digits',
      'auth.validation_password_required': 'Please enter a password',
      'auth.validation_password_short':
          'Password must have at least 8 characters',
      'auth.validation_confirm_password_required':
          'Please confirm your password',
      'auth.validation_confirm_password_mismatch':
          'Confirmation password does not match',

      'profile.title': 'Profile',
      'profile.loading': 'Loading profile',
      'profile.stats.plans': 'Plans',
      'profile.stats.groups': 'Groups',
      'profile.stats.friends': 'Friends',
      'profile.personal_info': 'Personal information',
      'profile.username': 'Username',
      'profile.full_name': 'Full name',
      'profile.phone': 'Phone number',
      'profile.birth_date': 'Birth date',
      'profile.bio': 'Bio',
      'profile.not_updated': 'Not updated',
      'profile.logout': 'Sign out',
      'profile.edit_info': 'Edit profile',
      'profile.bio_hint': 'About you',
      'profile.updated_success': 'Profile updated successfully',
      'profile.updated_error': 'Something went wrong. Please try again.',

      'plans.title': 'Your plans',
      'plans.group_title': '{group} - Plans',
      'plans.create_tooltip': 'Create new plan',
      'plans.load_more_error': 'Could not load the next page',
      'plans.all_loaded': 'All plans are shown',
      'plans.empty_title': 'No plans yet',
      'plans.empty_group_description': 'This group has no plans yet',
      'plans.empty_personal': 'No personal plans yet',
      'plans.empty_group': 'No group plans yet',
      'plans.empty_default': 'Create your first plan',
      'plans.created_success': 'Plan created successfully',
      'plans.loading_more': 'Loading more',

      'groups.title': 'Groups',
      'groups.create': 'Create group',
      'groups.created_success': 'Group created successfully',
      'groups.load_error': 'Could not load groups: {error}',
      'groups.unnamed': 'Unnamed group',
      'groups.member_count': '{count} members',
      'groups.left_success': 'Left group successfully',
      'groups.empty_title': 'No groups yet',
      'groups.empty_description':
          'Create your first group to start planning together',

      'group_details.title': 'Group details',
      'group_details.chat_tooltip': 'Group chat',
      'group_details.update_cover_tooltip': 'Update cover image',
      'group_details.update_cover_loading': 'Updating cover image...',
      'group_details.update_cover_success': 'Cover image updated',
      'group_details.unnamed': 'Unnamed group',
      'group_details.admin_label': 'Administrator',
      'group_details.members_title': 'Members',
      'group_details.add_member': 'Add member',
      'group_details.tap_member_remove': 'Tap a member to manage permissions',
      'group_details.tap_to_remove': 'Manage',
      'group_details.role_admin': 'Admin',
      'group_details.role_plan_creator': 'Plan creator',
      'group_details.role_member': 'Member',
      'group_details.other_members': '... and {count} more members',
      'group_details.plans_title': 'Group plans ({count})',
      'group_details.create_plan': 'Create new plan',
      'group_details.loading_plans': 'Loading plans...',
      'group_details.empty_plans_title': 'No plans yet',
      'group_details.empty_plans_description':
          'Create the first plan for this group',
      'group_details.plans_list': 'Plans list:',
      'group_details.add_member_success': 'Member added successfully',
      'group_details.leave_title': 'Leave group',
      'group_details.leave_confirm': 'Do you want to leave "{group}"?',
      'group_details.leave_action': 'Leave group',
      'group_details.leave_success': 'Left group successfully',
      'group_details.member_options_remove': 'Remove from group',
      'group_details.member_options_remove_description':
          'This member will no longer have access to the group',
      'group_details.grant_plan_creator': 'Grant plan creator',
      'group_details.grant_plan_creator_description':
          'Allow this member to create group plans',
      'group_details.revoke_plan_creator': 'Revoke plan creator',
      'group_details.revoke_plan_creator_description':
          'Return this member to regular member permissions',
      'group_details.grant_plan_creator_success':
          'Granted plan creator permission to "{name}"',
      'group_details.revoke_plan_creator_success':
          'Revoked plan creator permission from "{name}"',
      'group_details.remove_member_title': 'Remove member',
      'group_details.remove_member_confirm':
          'Do you want to remove "{name}" from the group?',
      'group_details.remove_member_success': 'Removed "{name}" from the group',
      'group_details.add_member_dialog_title': 'Add member',
      'group_details.add_member_loading': 'Loading friends...',
      'group_details.add_member_error': 'Could not load friends list: {error}',
      'group_details.add_member_search_hint': 'Search friends...',
      'group_details.add_member_empty':
          'No friends available to add to the group',

      'group_form.title_create': 'Create group',
      'group_form.title_edit': 'Edit group',
      'group_form.avatar_title': 'Group avatar',
      'group_form.cover_title': 'Group cover image (optional)',
      'group_form.cover_loading': 'Loading cover image...',
      'group_form.cover_pick': 'Choose cover image',
      'group_form.name_label': 'Group name',
      'group_form.name_required': 'Please enter a group name',
      'group_form.description_label': 'Description',
      'group_form.members_title': 'Group members',
      'group_form.members_requirement':
          'At least 2 members are required to create a group',
      'group_form.no_friends': 'No friends available to add to the group',

      'friends.title': 'Friends',
      'friends.tab_friends': 'Friends ({count})',
      'friends.tab_requests': 'Requests',
      'friends.accept_success': 'Friend request accepted',
      'friends.reject_success': 'Friend request declined',
      'friends.load_friends_error': 'Could not load friends list',
      'friends.load_requests_error': 'Could not load friend requests',
      'friends.empty_title': 'No friends yet',
      'friends.empty_description': 'Search and connect with people you know',
      'friends.empty_requests_title': 'No requests',
      'friends.empty_requests_description':
          'Incoming friend requests will appear here',
      'friends.online': 'Online',
      'friends.offline': 'Offline',
      'friends.request_sent': 'Sent you a friend request',
      'friends.decline': 'Decline',
      'friends.accept': 'Accept',

      'user_profile.access_denied': 'You cannot access this profile page',
      'user_profile.access_denied_default': 'Profile access is unavailable',
      'user_profile.access_denied_description':
          'You do not have permission to view this user.',
      'user_profile.back': 'Go back',
      'user_profile.load_error': 'Could not load profile: {error}',
      'user_profile.request_sent': 'Friend request sent',
      'user_profile.accept_success': 'Friend request accepted',
      'user_profile.reject_success': 'Friend request declined',
      'user_profile.error': 'Error: {error}',
      'user_profile.unfriend_confirm':
          'Do you want to remove {name} from your friends?',
      'user_profile.unfriend_success': 'Friend removed',
      'user_profile.block_title': 'Confirm block',
      'user_profile.block_confirm':
          'Do you want to block {name}? They will no longer be able to message you or send friend requests.',
      'user_profile.block_action': 'Block',
      'user_profile.block_success': 'User blocked',
      'user_profile.unblock_title': 'Unblock',
      'user_profile.unblock_confirm': 'Do you want to unblock {name}?',
      'user_profile.unblock_action': 'Unblock',
      'user_profile.unblock_success': 'User unblocked',
      'user_profile.menu_block': 'Block user',
      'user_profile.menu_unblock': 'Unblock',
      'user_profile.online': 'Online',
      'user_profile.friends': 'Friends',
      'user_profile.unfriend': 'Remove friend',
      'user_profile.pending_sent': 'Request sent',
      'user_profile.pending_received': 'Accept request',
      'user_profile.pending_decline': 'Decline',
      'user_profile.blocked': 'Blocked',
      'user_profile.add_friend': 'Add friend',
      'user_profile.personal_info': 'Personal information',
      'user_profile.display_name': 'Display name',
      'user_profile.status': 'Status',
      'user_profile.joined': 'Joined',
      'user_profile.last_active': 'Last active',

      'plan.status.draft': 'Draft',
      'plan.status.active': 'Active',
      'plan.status.completed': 'Completed',
      'plan.status.cancelled': 'Cancelled',
      'plan.status.upcoming': 'Upcoming',
      'plan.status.ongoing': 'Ongoing',
      'plan.activities_label.one': '{count} activity',
      'plan.activities_label.other': '{count} activities',
      'plan.duration_days.one': '{count} day',
      'plan.duration_days.other': '{count} days',

      'notifications.title': 'Notifications',
      'notifications.mark_all_as_read': 'Mark all as read',
      'notifications.empty_title': 'No notifications yet',
      'notifications.empty_description':
          'New plan, group, and chat updates will appear here.',
      'notifications.type.plan_reminder': 'Plan reminder',
      'notifications.type.group_join': 'Group activity',
      'notifications.type.group_invite': 'Group invite',
      'notifications.type.role_changed': 'Role changed',
      'notifications.type.plan_updated': 'Plan updated',
      'notifications.type.new_message': 'New message',
      'notifications.type.budget_alert': 'Budget alert',
      'notifications.type.large_expense': 'Large expense',
      'notifications.time.just_now': 'Just now',
      'notifications.time.minutes': '{value}m',
      'notifications.time.hours': '{value}h',
      'notifications.time.days': '{value}d',

      'analytics.title': 'Analytics Dashboard',
      'analytics.unavailable_title': 'Analytics unavailable',
      'analytics.unavailable_description':
          'This dashboard is available only to staff accounts.',
      'analytics.hero_eyebrow': 'Product Pulse',
      'analytics.hero_title': 'Usage and engagement trends',
      'analytics.latest_aggregated_day': 'Latest aggregated day: {date}',
      'analytics.trend_view': 'Trend View',
      'analytics.no_data_title': 'No analytics data',
      'analytics.no_data_description':
          'No trend data is available for this metric yet.',
      'analytics.range_totals': 'Range totals',
      'analytics.top_entities': 'Top entities',
      'analytics.top_plans': 'Top plans',
      'analytics.top_groups': 'Top groups',
      'analytics.total_plans_created': 'Plans created',
      'analytics.total_plans_completed': 'Plans completed',
      'analytics.total_group_joins': 'Group joins',
      'analytics.total_notifications_sent': 'Notifications sent',
      'analytics.total_notifications_opened': 'Notifications opened',
      'analytics.range.7d': '7 days',
      'analytics.range.30d': '30 days',
      'analytics.range.90d': '90 days',
      'analytics.range.180d': '180 days',
      'analytics.metric.dau': 'Daily Active Users',
      'analytics.metric.mau': 'Monthly Active Users',
      'analytics.metric.plan_creation_rate': 'Plan Creation Rate',
      'analytics.metric.plan_completion_rate': 'Plan Completion Rate',
      'analytics.metric.group_join_rate': 'Group Join Rate',
      'analytics.metric.notification_open_rate': 'Notification Open Rate',
      'analytics.empty_series': 'No time-series data available',
      'analytics.empty_ranked_entities': 'No ranked entities yet',

      'budget.overview_title': 'Budget Overview',
      'budget.quick_add': 'Quick add',
      'budget.track_description':
          'Track budget health, per-user contributions, and recent spending.',
      'budget.view_expenses': 'View expenses',
      'budget.add_expense': 'Add expense',
      'budget.update_budget': 'Update budget',
      'budget.set_budget': 'Set budget',
      'budget.expense_added_successfully': 'Expense added successfully',
      'budget.expense_added': 'Expense added',
      'budget.dialog_title_update': 'Update budget',
      'budget.dialog_title_set': 'Set budget',
      'budget.total_budget': 'Total budget',
      'budget.currency': 'Currency',
      'budget.validation_non_negative_amount':
          'Enter a valid non-negative amount',
      'budget.validation_currency_length':
          'Currency must be between 3 and 10 characters',
      'budget.saved_successfully': 'Budget saved successfully',
      'budget.summary_title': 'Budget Overview',
      'budget.summary_spent': '{value}% spent',
      'budget.summary_no_budget': 'No budget configured yet',
      'budget.metric_budget': 'Budget',
      'budget.metric_spent': 'Spent',
      'budget.metric_remaining': 'Remaining',
      'budget.metric_expenses': 'Expenses',
      'budget.over_budget': 'This plan is over budget.',
      'budget.near_limit': 'This plan is close to its budget limit.',
      'budget.breakdown_title': 'Per-user breakdown',
      'budget.breakdown_empty': 'No expense data yet.',
      'budget.expenses_title': 'Plan Expenses',
      'budget.filter_by_category': 'Filter by category',
      'budget.expenses_empty_title': 'No expenses yet',
      'budget.expenses_empty_description':
          'New plan expenses will appear here.',
      'budget.form_title': 'Add Expense',
      'budget.form_description':
          'Record a plan expense and update the shared budget in one flow.',
      'budget.amount': 'Amount',
      'budget.category': 'Category',
      'budget.description': 'Description',
      'budget.amount_hint': '250000',
      'budget.category_hint': 'Food, Transport, Hotel...',
      'budget.description_hint': 'Optional note for this expense',
      'budget.saving': 'Saving...',
      'budget.validation_amount_positive':
          'Enter a valid amount greater than zero',
      'budget.validation_category_required': 'Category is required',
      'budget.validation_category_too_long': 'Category is too long',
      'budget.chart_title': 'Spending Trend',
      'budget.chart_empty': 'No spending trend data yet.',

      'chat.location_default_title': 'Location',
      'chat.tap_to_open_map': 'Tap to open map',
      'chat.file_default_name': 'File',
      'chat.tap_to_open_file': 'Tap to open file',
      'chat.realtime_retrying': 'Realtime disconnected. Retrying...',
      'chat.realtime_connecting': 'Connecting realtime...',
      'chat.send_message_failed': 'Could not send message. Please try again.',
      'chat.send_image_failed': 'Could not send image. Please try again.',
      'chat.share_location_failed':
          'Could not share location. Please try again.',
      'chat.send_file_failed': 'Could not send file. Please try again.',
      'chat.loading_messages_failed':
          'Could not load messages. Please try again.',
      'chat.empty_title': 'No messages yet',
      'chat.empty_description': 'Start the conversation!',
      'chat.feature_unavailable': 'This feature is not available yet.',

      'location_picker.title': 'Choose location',
      'location_picker.confirm': 'Confirm',
      'location_picker.search_hint': 'Search for a place...',
      'location_picker.location_service_disabled':
          'Location service is turned off.',
      'location_picker.permission_denied':
          'The app does not have permission to access location.',
      'location_picker.current_location_error':
          'Could not get the current location.',
      'location_picker.coordinates': 'Coordinates: {value}',
      'location_picker.select_this_location': 'Use this location',
      'location_picker.selected_name': 'Selected location',
      'map.title': 'Map',
      'map.selected_location': 'Current location',
      'map.send_location': 'Send location',
      'map.choose_conversation': 'Send to conversation',
      'map.choose_conversation_hint':
          'Choose a conversation to share your current location.',
      'map.load_conversations_failed': 'Could not load conversations.',
      'map.no_conversations_title': 'No conversations yet',
      'map.no_conversations_description':
          'Start a conversation before sharing your location.',
      'map.sent_success': 'Location sent to {conversation}.',
      'map.send_failed': 'Could not send location. Please try again.',
      'map.direct_conversation': 'Direct conversation',
      'map.group_conversation': 'Group conversation · {count} members',

      'schedule.stats_title': 'Plan statistics',
      'schedule.load_detail_error': 'Could not load details: {error}',
      'schedule.delete_loading': 'Deleting activity...',
      'schedule.delete_success': 'Deleted "{title}"',
      'schedule.delete_error': 'Could not delete activity: {error}',

      'audit.refresh': 'Refresh audit logs',
      'audit.action': 'Action',
      'audit.all_actions': 'All actions',
      'audit.user': 'User',
      'audit.all_users': 'All users',
      'audit.empty': 'No audit activity matches the current filters.',
      'audit.load_more': 'Load more',

      'plan.details_title': 'Plan details',
      'plan.description': 'Description',
      'plan.time': 'Time',
      'plan.start': 'Start',
      'plan.end': 'End',
      'plan.activities': 'Activities',
      'plan.no_activities': 'No activities yet',
      'plan.audit_log_title': 'Plan Audit Log',
      'plan.updated_success': 'Plan updated successfully',
      'plan.edit': 'Edit',
      'plan.delete': 'Delete',
      'plan.delete_title': 'Delete plan',
      'plan.delete_confirm': 'Do you want to delete "{title}"?',
      'plan.deleted_success': 'Plan deleted',
      'plan.cancel_plan': 'Cancel plan',
      'plan.cancel_title': 'Cancel plan',
      'plan.cancel_confirm':
          'Cancel "{title}"? This is only available before the plan starts.',
      'plan.cancelled_success': 'Plan cancelled',
      'plan.cancel_unavailable': 'Only upcoming plans can be cancelled.',
      'plan.schedule_tooltip': 'View schedule',
      'plan.add_activity_tooltip': 'Add activity',
      'plan.creator': 'Creator',
      'plan.overview': 'Overview',
      'plan.group_plan': 'Group plan',
      'plan.personal_plan': 'Personal plan',
      'plan.public': 'Public',
      'plan.private': 'Private',
      'plan.activities_count': 'Activities: {count}',
      'plan.total_estimated': 'Estimated total: {amount}',
      'plan.plan_fallback_title': 'Plan',
      'plan.schedule_fallback_title': 'Schedule',
      'plan.view_more': 'View more ({count})',
      'plan.budget_card_title': 'Budget Tracking',
      'plan.budget_card_description':
          'Track spending, balances, and per-user contributions.',

      'plan_form.title_create': 'Create plan',
      'plan_form.title_edit': 'Edit plan',
      'plan_form.field_title': 'Plan title',
      'plan_form.field_description': 'Description',
      'plan_form.field_type': 'Plan type',
      'plan_form.type_personal': 'Personal plan',
      'plan_form.type_group': 'Group plan',
      'plan_form.select_group': 'Select group',
      'plan_form.validation_title_required': 'Please enter a plan title',
      'plan_form.validation_group_required': 'Please select a group',
      'plan_form.select_start_date': 'Select start date',
      'plan_form.select_end_date': 'Select end date',
      'plan_form.start_label': 'Start: {value}',
      'plan_form.end_label': 'End: {value}',
      'plan_form.public': 'Public',
      'plan_form.public_description_public': 'Everyone can view this plan',
      'plan_form.public_description_private': 'Only me',
      'plan_form.save_changes': 'Save changes',
      'plan_form.create': 'Create',
      'plan_form.validation_end_after_start':
          'End date must be after start date',

      'activity_form.title_create': 'Create new activity',
      'activity_form.plan_label': 'Plan:',
      'activity_form.field_title': 'Activity title *',
      'activity_form.validation_title_required':
          'Please enter an activity title',
      'activity_form.field_type': 'Activity type',
      'activity_form.field_description': 'Description',
      'activity_form.section_time': 'Time',
      'activity_form.select_time': 'Select time',
      'activity_form.section_location': 'Location',
      'activity_form.tap_select_location': 'Tap to select location',
      'activity_form.selected_location': 'Selected location',
      'activity_form.field_cost': 'Estimated cost',
      'activity_form.field_notes': 'Notes',
      'activity_form.submit_create': 'Create activity',

      'activity.type.eating': 'Eating',
      'activity.type.resting': 'Resting',
      'activity.type.moving': 'Moving',
      'activity.type.sightseeing': 'Sightseeing',
      'activity.type.shopping': 'Shopping',
      'activity.type.entertainment': 'Entertainment',
      'activity.type.event': 'Event',
      'activity.type.sport': 'Sport',
      'activity.type.study': 'Study',
      'activity.type.work': 'Work',
      'activity.type.other': 'Other',

      'activity_details.completed': 'Completed',
      'activity_details.not_completed': 'Not completed',
      'activity_details.type': 'Activity type',
      'activity_details.description': 'Description',
      'activity_details.time': 'Time',
      'activity_details.location': 'Location',
      'activity_details.open_map': 'Open map',
      'activity_details.directions': 'Directions',
      'activity_details.view_on_map': 'View on map',
      'activity_details.notes': 'Notes',
      'activity_details.status': 'Status',
      'activity_details.duration': 'Duration: {value}',
      'activity_details.start': 'Start: {value}',
      'activity_details.end': 'End: {value}',
      'activity_details.close': 'Close',
      'activity_details.edit': 'Edit',
      'activity_details.delete_tooltip': 'Delete activity',
      'activity_details.delete_confirm_title': 'Delete activity',
      'activity_details.delete_confirm_message':
          'Do you want to delete "{title}"?',
    },
    'vi': {
      'common.app_name': 'PlanPal',
      'common.retry': 'Thử lại',
      'common.refresh': 'Làm mới',
      'common.cancel': 'Hủy',
      'common.save': 'Lưu',
      'common.close': 'Đóng',
      'common.confirm': 'Xác nhận',
      'common.search': 'Tìm kiếm',
      'common.error': 'Lỗi',
      'common.delete': 'Xóa',
      'common.edit': 'Chỉnh sửa',
      'common.other': 'Khác',
      'common.unknown': 'Không rõ',
      'common.loading_session': 'Đang khởi tạo phiên làm việc...',
      'common.language': 'Ngôn ngữ',
      'common.language_english': 'Tiếng Anh',
      'common.language_vietnamese': 'Tiếng Việt',
      'common.not_logged_in': 'Chưa đăng nhập',
      'common.all': 'Tất cả',
      'common.read': 'Đã đọc',
      'common.unread': 'Chưa đọc',
      'common.just_now': 'Vừa xong',
      'common.minutes_ago': '{count} phút trước',
      'common.hours_ago': '{count} giờ trước',
      'common.days_ago': '{count} ngày trước',
      'common.view_all': 'Xem tất cả',
      'common.apply': 'Áp dụng',
      'common.add': 'Thêm',
      'common.quick_add': 'Thêm nhanh',
      'common.filter': 'Bộ lọc',
      'common.newest_first': 'Mới nhất trước',
      'common.oldest_first': 'Cũ nhất trước',
      'common.highest_amount': 'Số tiền cao nhất',
      'common.lowest_amount': 'Số tiền thấp nhất',
      'common.open': 'Mở',
      'common.free': 'Miễn phí',
      'common.clear_filters': 'Xóa bộ lọc',
      'common.from_date': 'Từ ngày',
      'common.to_date': 'Đến ngày',
      'common.yes': 'Có',
      'common.no': 'Không',
      'activity_collab.polling_fallback':
          'Realtime tạm thời không khả dụng. Lịch đang được đồng bộ theo chu kỳ.',
      'activity_collab.realtime_connecting':
          'Đang kết nối cập nhật realtime...',
      'activity_collab.edited_by': '{user} vừa sửa: {fields}',
      'activity_collab.edited_fields': 'Các trường vừa thay đổi: {fields}',
      'activity_collab.version_label': 'Phiên bản',
      'activity_collab.current_version': 'Phiên bản hiện tại: {version}',
      'activity_collab.save_changes': 'Lưu thay đổi',
      'activity_collab.conflict_title': 'Phát hiện xung đột hoạt động',
      'activity_collab.conflict_versions':
          'Phiên bản của bạn: {client} | Phiên bản máy chủ: {server}',
      'activity_collab.conflict_fields': 'Các trường xung đột: {fields}',
      'activity_collab.use_server': 'Tải bản mới từ máy chủ',
      'activity_collab.overwrite': 'Ghi đè bằng thay đổi của tôi',
      'activity_collab.server_version_loaded':
          'Bản mới nhất từ máy chủ đã được nạp vào biểu mẫu.',

      'home.notifications': 'Thông báo',
      'home.conversations': 'Cuộc hội thoại',
      'home.groups': 'Nhóm',
      'home.plans': 'Kế hoạch',
      'home.analytics': 'Phân tích',
      'home.profile': 'Cá nhân',
      'home.greeting_morning': 'Chào buổi sáng!',
      'home.greeting_afternoon': 'Chào buổi chiều!',
      'home.greeting_evening': 'Chào buổi tối!',
      'home.ready_for_trip': 'Sẵn sàng cho chuyến phiêu lưu tiếp theo?',
      'home.quick_actions': 'Hành động nhanh',
      'home.create_plan': 'Tạo kế hoạch',
      'home.join_group': 'Tham gia nhóm',
      'home.find_friends': 'Tìm bạn bè',
      'home.map': 'Bản đồ',
      'home.recent_plans': 'Kế hoạch gần đây',
      'home.active_groups': 'Nhóm hoạt động',
      'home.no_plans_title': 'Chưa có kế hoạch',
      'home.no_plans_description':
          'Tạo kế hoạch đầu tiên cho hành trình tiếp theo.',
      'home.no_groups_title': 'Chưa có nhóm',
      'home.no_groups_description':
          'Tham gia hoặc tạo nhóm để phối hợp kế hoạch chung.',
      'home.group_prefix': 'Nhóm: {group}',
      'home.copyright': '© 2026 PlanPal',
      'home.language_sheet_title': 'Chọn ngôn ngữ',

      'auth.login_title': 'Đăng nhập PlanPal',
      'auth.username': 'Tên đăng nhập',
      'auth.password': 'Mật khẩu',
      'auth.enter_username': 'Nhập tên đăng nhập',
      'auth.enter_password': 'Nhập mật khẩu',
      'auth.login': 'Đăng nhập',
      'auth.no_account': 'Chưa có tài khoản?',
      'auth.register_now': 'Đăng ký ngay',
      'auth.register_title': 'Tạo tài khoản',
      'auth.register_subtitle':
          'Tham gia PlanPal để lên kế hoạch du lịch cùng bạn bè.',
      'auth.add_photo': 'Thêm ảnh',
      'auth.email': 'Email',
      'auth.first_name': 'Tên',
      'auth.last_name': 'Họ',
      'auth.phone_optional': 'Số điện thoại (tùy chọn)',
      'auth.confirm_password': 'Xác nhận mật khẩu',
      'auth.register': 'Đăng ký',
      'auth.registering': 'Đang đăng ký...',
      'auth.have_account': 'Đã có tài khoản?',
      'auth.pick_image_error': 'Không thể chọn ảnh: {error}',
      'auth.register_success': 'Đăng ký thành công.',
      'auth.register_verify_email':
          'Tài khoản đã được tạo. Vui lòng nhập mã 6 số đã gửi đến email.',
      'auth.register_failed': 'Đăng ký thất bại: {error}',
      'auth.verify_email_title': 'Xác thực email',
      'auth.verify_email_subtitle': 'Nhập mã xác thực 6 số đã gửi đến {email}.',
      'auth.verification_code': 'Mã xác thực',
      'auth.verify_email_action': 'Xác thực email',
      'auth.verifying': 'Đang xác thực...',
      'auth.resend_code': 'Gửi lại mã',
      'auth.resending_code': 'Đang gửi lại...',
      'auth.back_to_login': 'Quay lại đăng nhập',
      'auth.verify_email_success':
          'Email đã được xác thực. Bạn có thể đăng nhập.',
      'auth.verify_email_failed':
          'Mã xác thực không đúng hoặc đã hết hạn. Vui lòng thử lại.',
      'auth.verify_email_resend_success': 'Mã xác thực mới đã được gửi.',
      'auth.verify_email_resend_failed':
          'Không thể gửi lại mã xác thực. Vui lòng thử lại.',
      'auth.verify_email_code_required': 'Vui lòng nhập mã gồm 6 số',
      'auth.validation_username_required': 'Vui lòng nhập tên đăng nhập',
      'auth.validation_username_short': 'Tên đăng nhập phải có ít nhất 2 ký tự',
      'auth.validation_email_required': 'Vui lòng nhập email',
      'auth.validation_email_invalid': 'Email không hợp lệ',
      'auth.validation_first_name_required': 'Vui lòng nhập tên',
      'auth.validation_last_name_required': 'Vui lòng nhập họ',
      'auth.validation_phone_invalid': 'Số điện thoại không hợp lệ',
      'auth.validation_phone_length':
          'Số điện thoại phải có từ 9 đến 15 chữ số',
      'auth.validation_password_required': 'Vui lòng nhập mật khẩu',
      'auth.validation_password_short': 'Mật khẩu phải có ít nhất 8 ký tự',
      'auth.validation_confirm_password_required': 'Vui lòng xác nhận mật khẩu',
      'auth.validation_confirm_password_mismatch':
          'Mật khẩu xác nhận không khớp',

      'profile.title': 'Trang cá nhân',
      'profile.loading': 'Đang tải hồ sơ',
      'profile.stats.plans': 'Kế hoạch',
      'profile.stats.groups': 'Nhóm',
      'profile.stats.friends': 'Bạn bè',
      'profile.personal_info': 'Thông tin cá nhân',
      'profile.username': 'Tên đăng nhập',
      'profile.full_name': 'Họ tên',
      'profile.phone': 'Số điện thoại',
      'profile.birth_date': 'Ngày sinh',
      'profile.bio': 'Giới thiệu',
      'profile.not_updated': 'Chưa cập nhật',
      'profile.logout': 'Đăng xuất',
      'profile.edit_info': 'Chỉnh sửa thông tin',
      'profile.bio_hint': 'Giới thiệu bản thân',
      'profile.updated_success': 'Cập nhật thông tin thành công',
      'profile.updated_error': 'Đã xảy ra lỗi. Vui lòng thử lại.',

      'plans.title': 'Kế hoạch của bạn',
      'plans.group_title': '{group} - Kế hoạch',
      'plans.create_tooltip': 'Tạo kế hoạch mới',
      'plans.load_more_error': 'Không tải được trang tiếp theo',
      'plans.all_loaded': 'Đã hiển thị tất cả kế hoạch',
      'plans.empty_title': 'Chưa có kế hoạch nào',
      'plans.empty_group_description': 'Nhóm này chưa có kế hoạch nào',
      'plans.empty_personal': 'Chưa có kế hoạch cá nhân nào',
      'plans.empty_group': 'Chưa có kế hoạch nhóm nào',
      'plans.empty_default': 'Tạo kế hoạch đầu tiên của bạn',
      'plans.created_success': 'Tạo kế hoạch mới thành công',
      'plans.loading_more': 'Đang tải thêm',

      'groups.title': 'Nhóm',
      'groups.create': 'Tạo nhóm',
      'groups.created_success': 'Tạo nhóm thành công',
      'groups.load_error': 'Lỗi tải nhóm: {error}',
      'groups.unnamed': 'Nhóm không tên',
      'groups.member_count': '{count} thành viên',
      'groups.left_success': 'Đã rời nhóm thành công',
      'groups.empty_title': 'Chưa có nhóm nào',
      'groups.empty_description':
          'Tạo nhóm đầu tiên để bắt đầu lập kế hoạch cùng nhau',

      'group_details.title': 'Chi tiết nhóm',
      'group_details.chat_tooltip': 'Chat nhóm',
      'group_details.update_cover_tooltip': 'Cập nhật ảnh bìa',
      'group_details.update_cover_loading': 'Đang cập nhật ảnh bìa...',
      'group_details.update_cover_success': 'Ảnh bìa đã được cập nhật',
      'group_details.unnamed': 'Nhóm không tên',
      'group_details.admin_label': 'Quản trị viên',
      'group_details.members_title': 'Thành viên',
      'group_details.add_member': 'Thêm thành viên',
      'group_details.tap_member_remove': 'Nhấn vào thành viên để quản lý quyền',
      'group_details.tap_to_remove': 'Quản lý',
      'group_details.role_admin': 'Quản trị viên',
      'group_details.role_plan_creator': 'Người tạo kế hoạch',
      'group_details.role_member': 'Thành viên',
      'group_details.other_members': '... và {count} thành viên khác',
      'group_details.plans_title': 'Kế hoạch nhóm ({count})',
      'group_details.create_plan': 'Tạo kế hoạch mới',
      'group_details.loading_plans': 'Đang tải kế hoạch...',
      'group_details.empty_plans_title': 'Chưa có kế hoạch nào',
      'group_details.empty_plans_description':
          'Hãy tạo kế hoạch đầu tiên cho nhóm',
      'group_details.plans_list': 'Danh sách kế hoạch:',
      'group_details.add_member_success': 'Đã thêm thành viên thành công',
      'group_details.leave_title': 'Rời nhóm',
      'group_details.leave_confirm':
          'Bạn có chắc chắn muốn rời khỏi nhóm "{group}"?',
      'group_details.leave_action': 'Rời nhóm',
      'group_details.leave_success': 'Đã rời nhóm thành công',
      'group_details.member_options_remove': 'Xóa khỏi nhóm',
      'group_details.member_options_remove_description':
          'Thành viên sẽ không còn truy cập được nhóm',
      'group_details.grant_plan_creator': 'Cấp quyền tạo kế hoạch',
      'group_details.grant_plan_creator_description':
          'Cho phép thành viên này tạo kế hoạch nhóm',
      'group_details.revoke_plan_creator': 'Thu hồi quyền tạo kế hoạch',
      'group_details.revoke_plan_creator_description':
          'Đưa thành viên này về quyền thành viên thường',
      'group_details.grant_plan_creator_success':
          'Đã cấp quyền tạo kế hoạch cho "{name}"',
      'group_details.revoke_plan_creator_success':
          'Đã thu hồi quyền tạo kế hoạch của "{name}"',
      'group_details.remove_member_title': 'Xóa thành viên',
      'group_details.remove_member_confirm':
          'Bạn có chắc chắn muốn xóa "{name}" khỏi nhóm?',
      'group_details.remove_member_success': 'Đã xóa "{name}" khỏi nhóm',
      'group_details.add_member_dialog_title': 'Thêm thành viên',
      'group_details.add_member_loading': 'Đang tải danh sách bạn bè...',
      'group_details.add_member_error':
          'Không thể tải danh sách bạn bè: {error}',
      'group_details.add_member_search_hint': 'Tìm kiếm bạn bè...',
      'group_details.add_member_empty': 'Không có bạn bè nào để thêm vào nhóm',

      'group_form.title_create': 'Tạo nhóm',
      'group_form.title_edit': 'Sửa nhóm',
      'group_form.avatar_title': 'Ảnh đại diện nhóm',
      'group_form.cover_title': 'Ảnh bìa nhóm (tùy chọn)',
      'group_form.cover_loading': 'Đang tải ảnh bìa...',
      'group_form.cover_pick': 'Chọn ảnh bìa',
      'group_form.name_label': 'Tên nhóm',
      'group_form.name_required': 'Vui lòng nhập tên nhóm',
      'group_form.description_label': 'Mô tả',
      'group_form.members_title': 'Thành viên nhóm',
      'group_form.members_requirement': 'Cần ít nhất 2 thành viên để tạo nhóm',
      'group_form.no_friends': 'Không có bạn bè nào để thêm vào nhóm',

      'friends.title': 'Bạn bè',
      'friends.tab_friends': 'Bạn bè ({count})',
      'friends.tab_requests': 'Lời mời',
      'friends.accept_success': 'Đã chấp nhận lời mời kết bạn',
      'friends.reject_success': 'Đã từ chối lời mời kết bạn',
      'friends.load_friends_error': 'Không thể tải danh sách bạn bè',
      'friends.load_requests_error': 'Không thể tải lời mời kết bạn',
      'friends.empty_title': 'Chưa có bạn bè',
      'friends.empty_description':
          'Hãy tìm kiếm và kết bạn với những người bạn biết',
      'friends.empty_requests_title': 'Không có lời mời nào',
      'friends.empty_requests_description':
          'Các lời mời kết bạn sẽ xuất hiện ở đây',
      'friends.online': 'Đang online',
      'friends.offline': 'Offline',
      'friends.request_sent': 'Đã gửi lời mời kết bạn',
      'friends.decline': 'Từ chối',
      'friends.accept': 'Chấp nhận',

      'user_profile.access_denied': 'Bạn không thể truy cập trang cá nhân này',
      'user_profile.access_denied_default': 'Không thể truy cập trang cá nhân',
      'user_profile.access_denied_description':
          'Bạn không có quyền xem thông tin của người dùng này.',
      'user_profile.back': 'Quay lại',
      'user_profile.load_error': 'Lỗi tải thông tin: {error}',
      'user_profile.request_sent': 'Đã gửi lời mời kết bạn',
      'user_profile.accept_success': 'Đã chấp nhận lời mời kết bạn',
      'user_profile.reject_success': 'Đã từ chối lời mời kết bạn',
      'user_profile.error': 'Lỗi: {error}',
      'user_profile.unfriend_confirm':
          'Bạn có chắc muốn hủy kết bạn với {name}?',
      'user_profile.unfriend_success': 'Đã hủy kết bạn',
      'user_profile.block_title': 'Xác nhận chặn',
      'user_profile.block_confirm':
          'Bạn có chắc muốn chặn {name}? Họ sẽ không thể gửi tin nhắn hoặc lời mời kết bạn cho bạn nữa.',
      'user_profile.block_action': 'Chặn',
      'user_profile.block_success': 'Đã chặn người dùng',
      'user_profile.unblock_title': 'Bỏ chặn',
      'user_profile.unblock_confirm': 'Bạn có muốn bỏ chặn {name}?',
      'user_profile.unblock_action': 'Bỏ chặn',
      'user_profile.unblock_success': 'Đã bỏ chặn người dùng',
      'user_profile.menu_block': 'Chặn người dùng',
      'user_profile.menu_unblock': 'Bỏ chặn',
      'user_profile.online': 'Đang online',
      'user_profile.friends': 'Bạn bè',
      'user_profile.unfriend': 'Hủy kết bạn',
      'user_profile.pending_sent': 'Đã gửi lời mời',
      'user_profile.pending_received': 'Chấp nhận',
      'user_profile.pending_decline': 'Từ chối',
      'user_profile.blocked': 'Đã chặn',
      'user_profile.add_friend': 'Kết bạn',
      'user_profile.personal_info': 'Thông tin cá nhân',
      'user_profile.display_name': 'Tên hiển thị',
      'user_profile.status': 'Trạng thái',
      'user_profile.joined': 'Tham gia',
      'user_profile.last_active': 'Hoạt động cuối',

      'plan.status.draft': 'Bản nháp',
      'plan.status.active': 'Đang diễn ra',
      'plan.status.completed': 'Đã hoàn thành',
      'plan.status.cancelled': 'Đã hủy',
      'plan.status.upcoming': 'Sắp diễn ra',
      'plan.status.ongoing': 'Đang diễn ra',
      'plan.activities_label.one': '{count} hoạt động',
      'plan.activities_label.other': '{count} hoạt động',
      'plan.duration_days.one': '{count} ngày',
      'plan.duration_days.other': '{count} ngày',

      'notifications.title': 'Thông báo',
      'notifications.mark_all_as_read': 'Đánh dấu tất cả đã đọc',
      'notifications.empty_title': 'Chưa có thông báo',
      'notifications.empty_description':
          'Cập nhật mới về kế hoạch, nhóm và chat sẽ xuất hiện ở đây.',
      'notifications.type.plan_reminder': 'Nhắc kế hoạch',
      'notifications.type.group_join': 'Hoạt động nhóm',
      'notifications.type.group_invite': 'Lời mời nhóm',
      'notifications.type.role_changed': 'Thay đổi vai trò',
      'notifications.type.plan_updated': 'Kế hoạch cập nhật',
      'notifications.type.new_message': 'Tin nhắn mới',
      'notifications.type.budget_alert': 'Cảnh báo ngân sách',
      'notifications.type.large_expense': 'Chi phí lớn',
      'notifications.time.just_now': 'Vừa xong',
      'notifications.time.minutes': '{value}p',
      'notifications.time.hours': '{value}g',
      'notifications.time.days': '{value}n',

      'analytics.title': 'Bảng điều khiển phân tích',
      'analytics.unavailable_title': 'Không thể xem phân tích',
      'analytics.unavailable_description':
          'Chỉ tài khoản nhân sự mới có quyền xem bảng điều khiển này.',
      'analytics.hero_eyebrow': 'Nhịp hệ thống',
      'analytics.hero_title': 'Xu hướng sử dụng và tương tác',
      'analytics.latest_aggregated_day': 'Ngày tổng hợp mới nhất: {date}',
      'analytics.trend_view': 'Xu hướng',
      'analytics.no_data_title': 'Chưa có dữ liệu phân tích',
      'analytics.no_data_description':
          'Chưa có dữ liệu xu hướng cho chỉ số này.',
      'analytics.range_totals': 'Tổng trong khoảng',
      'analytics.top_entities': 'Thực thể nổi bật',
      'analytics.top_plans': 'Kế hoạch nổi bật',
      'analytics.top_groups': 'Nhóm nổi bật',
      'analytics.total_plans_created': 'Kế hoạch đã tạo',
      'analytics.total_plans_completed': 'Kế hoạch đã hoàn thành',
      'analytics.total_group_joins': 'Lượt tham gia nhóm',
      'analytics.total_notifications_sent': 'Thông báo đã gửi',
      'analytics.total_notifications_opened': 'Thông báo đã mở',
      'analytics.range.7d': '7 ngày',
      'analytics.range.30d': '30 ngày',
      'analytics.range.90d': '90 ngày',
      'analytics.range.180d': '180 ngày',
      'analytics.metric.dau': 'Người dùng hoạt động ngày',
      'analytics.metric.mau': 'Người dùng hoạt động tháng',
      'analytics.metric.plan_creation_rate': 'Tỷ lệ tạo kế hoạch',
      'analytics.metric.plan_completion_rate': 'Tỷ lệ hoàn thành kế hoạch',
      'analytics.metric.group_join_rate': 'Tỷ lệ tham gia nhóm',
      'analytics.metric.notification_open_rate': 'Tỷ lệ mở thông báo',
      'analytics.empty_series': 'Chưa có dữ liệu chuỗi thời gian',
      'analytics.empty_ranked_entities': 'Chưa có thực thể xếp hạng',

      'budget.overview_title': 'Tổng quan ngân sách',
      'budget.quick_add': 'Thêm nhanh',
      'budget.track_description':
          'Theo dõi sức khỏe ngân sách, đóng góp theo người dùng và chi tiêu gần đây.',
      'budget.view_expenses': 'Xem chi phí',
      'budget.add_expense': 'Thêm chi phí',
      'budget.update_budget': 'Cập nhật ngân sách',
      'budget.set_budget': 'Thiết lập ngân sách',
      'budget.expense_added_successfully': 'Đã thêm chi phí thành công',
      'budget.expense_added': 'Đã thêm chi phí',
      'budget.dialog_title_update': 'Cập nhật ngân sách',
      'budget.dialog_title_set': 'Thiết lập ngân sách',
      'budget.total_budget': 'Tổng ngân sách',
      'budget.currency': 'Đơn vị tiền',
      'budget.validation_non_negative_amount':
          'Nhập số tiền hợp lệ lớn hơn hoặc bằng 0',
      'budget.validation_currency_length':
          'Đơn vị tiền phải có từ 3 đến 10 ký tự',
      'budget.saved_successfully': 'Đã lưu ngân sách thành công',
      'budget.summary_title': 'Tổng quan ngân sách',
      'budget.summary_spent': 'Đã dùng {value}%',
      'budget.summary_no_budget': 'Chưa cấu hình ngân sách',
      'budget.metric_budget': 'Ngân sách',
      'budget.metric_spent': 'Đã chi',
      'budget.metric_remaining': 'Còn lại',
      'budget.metric_expenses': 'Khoản chi',
      'budget.over_budget': 'Kế hoạch này đã vượt ngân sách.',
      'budget.near_limit': 'Kế hoạch này đang gần chạm giới hạn ngân sách.',
      'budget.breakdown_title': 'Phân bổ theo người dùng',
      'budget.breakdown_empty': 'Chưa có dữ liệu chi phí.',
      'budget.expenses_title': 'Chi phí của kế hoạch',
      'budget.filter_by_category': 'Lọc theo danh mục',
      'budget.expenses_empty_title': 'Chưa có chi phí',
      'budget.expenses_empty_description':
          'Chi phí mới của kế hoạch sẽ xuất hiện ở đây.',
      'budget.form_title': 'Thêm chi phí',
      'budget.form_description':
          'Ghi nhận một khoản chi của kế hoạch và cập nhật ngân sách chung trong một luồng.',
      'budget.amount': 'Số tiền',
      'budget.category': 'Danh mục',
      'budget.description': 'Mô tả',
      'budget.amount_hint': '250000',
      'budget.category_hint': 'Ăn uống, di chuyển, khách sạn...',
      'budget.description_hint': 'Ghi chú tùy chọn cho khoản chi này',
      'budget.saving': 'Đang lưu...',
      'budget.validation_amount_positive': 'Nhập số tiền hợp lệ lớn hơn 0',
      'budget.validation_category_required': 'Danh mục là bắt buộc',
      'budget.validation_category_too_long': 'Danh mục quá dài',
      'budget.chart_title': 'Xu hướng chi tiêu',
      'budget.chart_empty': 'Chưa có dữ liệu xu hướng chi tiêu.',

      'chat.location_default_title': 'Vị trí',
      'chat.tap_to_open_map': 'Nhấn để mở bản đồ',
      'chat.file_default_name': 'Tệp',
      'chat.tap_to_open_file': 'Nhấn để mở tệp',
      'chat.realtime_retrying': 'Mất kết nối realtime. Đang thử lại...',
      'chat.realtime_connecting': 'Đang kết nối realtime...',
      'chat.send_message_failed': 'Không thể gửi tin nhắn. Vui lòng thử lại.',
      'chat.send_image_failed': 'Không thể gửi ảnh. Vui lòng thử lại.',
      'chat.share_location_failed':
          'Không thể chia sẻ vị trí. Vui lòng thử lại.',
      'chat.send_file_failed': 'Không thể gửi tệp. Vui lòng thử lại.',
      'chat.loading_messages_failed':
          'Không thể tải tin nhắn. Vui lòng thử lại.',
      'chat.empty_title': 'Chưa có tin nhắn',
      'chat.empty_description': 'Hãy bắt đầu cuộc trò chuyện!',
      'chat.feature_unavailable': 'Chức năng này chưa khả dụng.',

      'location_picker.title': 'Chọn vị trí',
      'location_picker.confirm': 'Xác nhận',
      'location_picker.search_hint': 'Tìm kiếm địa điểm...',
      'location_picker.location_service_disabled': 'Dịch vụ vị trí đang tắt.',
      'location_picker.permission_denied':
          'Ứng dụng chưa có quyền truy cập vị trí.',
      'location_picker.current_location_error':
          'Không thể lấy vị trí hiện tại.',
      'location_picker.coordinates': 'Tọa độ: {value}',
      'location_picker.select_this_location': 'Chọn vị trí này',
      'location_picker.selected_name': 'Vị trí đã chọn',
      'map.title': 'Bản đồ',
      'map.selected_location': 'Vị trí hiện tại',
      'map.send_location': 'Gửi vị trí',
      'map.choose_conversation': 'Gửi vào cuộc hội thoại',
      'map.choose_conversation_hint':
          'Chọn một cuộc hội thoại để chia sẻ vị trí hiện tại của bạn.',
      'map.load_conversations_failed': 'Không thể tải danh sách hội thoại.',
      'map.no_conversations_title': 'Chưa có cuộc hội thoại',
      'map.no_conversations_description':
          'Hãy bắt đầu một cuộc hội thoại trước khi chia sẻ vị trí.',
      'map.sent_success': 'Đã gửi vị trí đến {conversation}.',
      'map.send_failed': 'Không thể gửi vị trí. Vui lòng thử lại.',
      'map.direct_conversation': 'Cuộc hội thoại trực tiếp',
      'map.group_conversation': 'Cuộc hội thoại nhóm · {count} thành viên',

      'schedule.stats_title': 'Thống kê kế hoạch',
      'schedule.load_detail_error': 'Không thể tải chi tiết: {error}',
      'schedule.delete_loading': 'Đang xóa hoạt động...',
      'schedule.delete_success': 'Đã xóa hoạt động "{title}"',
      'schedule.delete_error': 'Không thể xóa hoạt động: {error}',

      'audit.refresh': 'Làm mới nhật ký',
      'audit.action': 'Hành động',
      'audit.all_actions': 'Tất cả hành động',
      'audit.user': 'Người dùng',
      'audit.all_users': 'Tất cả người dùng',
      'audit.empty': 'Không có hoạt động nào khớp với bộ lọc hiện tại.',
      'audit.load_more': 'Tải thêm',

      'plan.details_title': 'Chi tiết kế hoạch',
      'plan.description': 'Mô tả',
      'plan.time': 'Thời gian',
      'plan.start': 'Bắt đầu',
      'plan.end': 'Kết thúc',
      'plan.activities': 'Hoạt động',
      'plan.no_activities': 'Chưa có hoạt động',
      'plan.audit_log_title': 'Nhật ký kế hoạch',
      'plan.updated_success': 'Cập nhật kế hoạch thành công',
      'plan.edit': 'Chỉnh sửa',
      'plan.delete': 'Xóa',
      'plan.delete_title': 'Xóa kế hoạch',
      'plan.delete_confirm': 'Bạn có chắc muốn xóa "{title}"?',
      'plan.deleted_success': 'Đã xóa kế hoạch',
      'plan.cancel_plan': 'Hủy kế hoạch',
      'plan.cancel_title': 'Hủy kế hoạch',
      'plan.cancel_confirm':
          'Hủy "{title}"? Chỉ có thể hủy khi kế hoạch chưa bắt đầu.',
      'plan.cancelled_success': 'Đã hủy kế hoạch',
      'plan.cancel_unavailable': 'Chỉ có thể hủy kế hoạch sắp diễn ra.',
      'plan.schedule_tooltip': 'Xem lịch trình',
      'plan.add_activity_tooltip': 'Thêm hoạt động',
      'plan.creator': 'Người tạo',
      'plan.overview': 'Tổng quan',
      'plan.group_plan': 'Kế hoạch nhóm',
      'plan.personal_plan': 'Kế hoạch cá nhân',
      'plan.public': 'Công khai',
      'plan.private': 'Riêng tư',
      'plan.activities_count': 'Hoạt động: {count}',
      'plan.total_estimated': 'Tổng dự kiến: {amount}',
      'plan.plan_fallback_title': 'Kế hoạch',
      'plan.schedule_fallback_title': 'Lịch trình',
      'plan.view_more': 'Xem thêm ({count})',
      'plan.budget_card_title': 'Theo dõi ngân sách',
      'plan.budget_card_description':
          'Theo dõi chi tiêu, số dư và đóng góp theo từng người dùng.',

      'plan_form.title_create': 'Tạo kế hoạch',
      'plan_form.title_edit': 'Sửa kế hoạch',
      'plan_form.field_title': 'Tiêu đề kế hoạch',
      'plan_form.field_description': 'Mô tả',
      'plan_form.field_type': 'Loại kế hoạch',
      'plan_form.type_personal': 'Kế hoạch cá nhân',
      'plan_form.type_group': 'Kế hoạch nhóm',
      'plan_form.select_group': 'Chọn nhóm',
      'plan_form.validation_title_required': 'Vui lòng nhập tiêu đề kế hoạch',
      'plan_form.validation_group_required': 'Vui lòng chọn nhóm',
      'plan_form.select_start_date': 'Chọn ngày bắt đầu',
      'plan_form.select_end_date': 'Chọn ngày kết thúc',
      'plan_form.start_label': 'Bắt đầu: {value}',
      'plan_form.end_label': 'Kết thúc: {value}',
      'plan_form.public': 'Công khai',
      'plan_form.public_description_public': 'Mọi người có thể xem kế hoạch',
      'plan_form.public_description_private': 'Chỉ mình tôi',
      'plan_form.save_changes': 'Lưu thay đổi',
      'plan_form.create': 'Tạo',
      'plan_form.validation_end_after_start':
          'Ngày kết thúc phải sau ngày bắt đầu',

      'activity_form.title_create': 'Tạo hoạt động mới',
      'activity_form.plan_label': 'Kế hoạch:',
      'activity_form.field_title': 'Tên hoạt động *',
      'activity_form.validation_title_required': 'Vui lòng nhập tên hoạt động',
      'activity_form.field_type': 'Loại hoạt động',
      'activity_form.field_description': 'Mô tả',
      'activity_form.section_time': 'Thời gian',
      'activity_form.select_time': 'Chọn thời gian',
      'activity_form.section_location': 'Địa điểm',
      'activity_form.tap_select_location': 'Chạm để chọn vị trí',
      'activity_form.selected_location': 'Vị trí đã chọn',
      'activity_form.field_cost': 'Chi phí ước tính',
      'activity_form.field_notes': 'Ghi chú',
      'activity_form.submit_create': 'Tạo hoạt động',

      'activity.type.eating': 'Ăn uống',
      'activity.type.resting': 'Nghỉ ngơi',
      'activity.type.moving': 'Di chuyển',
      'activity.type.sightseeing': 'Tham quan',
      'activity.type.shopping': 'Mua sắm',
      'activity.type.entertainment': 'Giải trí',
      'activity.type.event': 'Sự kiện',
      'activity.type.sport': 'Thể thao',
      'activity.type.study': 'Học tập',
      'activity.type.work': 'Công việc',
      'activity.type.other': 'Khác',

      'activity_details.completed': 'Đã hoàn thành',
      'activity_details.not_completed': 'Chưa hoàn thành',
      'activity_details.type': 'Loại hoạt động',
      'activity_details.description': 'Mô tả',
      'activity_details.time': 'Thời gian',
      'activity_details.location': 'Vị trí',
      'activity_details.open_map': 'Mở bản đồ',
      'activity_details.directions': 'Chỉ đường',
      'activity_details.view_on_map': 'Xem trên bản đồ',
      'activity_details.notes': 'Ghi chú',
      'activity_details.status': 'Trạng thái',
      'activity_details.duration': 'Thời gian: {value}',
      'activity_details.start': 'Bắt đầu: {value}',
      'activity_details.end': 'Kết thúc: {value}',
      'activity_details.close': 'Đóng',
      'activity_details.edit': 'Chỉnh sửa',
      'activity_details.delete_tooltip': 'Xóa hoạt động',
      'activity_details.delete_confirm_title': 'Xóa hoạt động',
      'activity_details.delete_confirm_message':
          'Bạn có chắc chắn muốn xóa hoạt động "{title}"?',
    },
  };

  String t(String key, {Map<String, String> params = const {}}) {
    final language = AppLocaleStore.resolve(locale).languageCode;
    final value =
        _translations[language]?[key] ??
        _translations[AppLocaleStore.fallbackLocale.languageCode]?[key] ??
        key;
    if (params.isEmpty) {
      return value;
    }
    var resolved = value;
    for (final entry in params.entries) {
      resolved = resolved.replaceAll('{${entry.key}}', entry.value);
    }
    return resolved;
  }

  String languageName(String code) {
    switch (code) {
      case 'en':
        return t('common.language_english');
      case 'vi':
      default:
        return t('common.language_vietnamese');
    }
  }

  String notificationTypeLabel(String type) {
    switch (type) {
      case 'PLAN_REMINDER':
        return t('notifications.type.plan_reminder');
      case 'GROUP_JOIN':
        return t('notifications.type.group_join');
      case 'GROUP_INVITE':
        return t('notifications.type.group_invite');
      case 'ROLE_CHANGED':
        return t('notifications.type.role_changed');
      case 'PLAN_UPDATED':
        return t('notifications.type.plan_updated');
      case 'NEW_MESSAGE':
        return t('notifications.type.new_message');
      case 'BUDGET_ALERT':
        return t('notifications.type.budget_alert');
      case 'LARGE_EXPENSE':
        return t('notifications.type.large_expense');
      default:
        return type.replaceAll('_', ' ');
    }
  }

  String analyticsMetricLabel(String metricApiValue) {
    return t('analytics.metric.$metricApiValue');
  }

  String analyticsRangeLabel(String rangeApiValue) {
    return t('analytics.range.$rangeApiValue');
  }

  String activityTypeLabel(String value) {
    return t('activity.type.$value');
  }

  String activityFieldLabel(String field) {
    switch (field) {
      case 'title':
        return t('activity_form.field_title');
      case 'description':
        return t('activity_form.field_description');
      case 'activity_type':
        return t('activity_form.field_type');
      case 'start_time':
        return t('plan.start');
      case 'end_time':
        return t('plan.end');
      case 'location_name':
      case 'location_address':
      case 'latitude':
      case 'longitude':
      case 'goong_place_id':
        return t('activity_form.section_location');
      case 'estimated_cost':
        return t('activity_form.field_cost');
      case 'notes':
        return t('activity_form.field_notes');
      case 'is_completed':
        return t('activity_details.status');
      default:
        return field;
    }
  }

  String planStatusLabel(String value) {
    return t('plan.status.$value');
  }

  String planTypeLabel(String value) {
    switch (value) {
      case 'group':
        return t('plan.group_plan');
      case 'personal':
        return t('plan.personal_plan');
      default:
        return t('common.other');
    }
  }

  String activityCountLabel(int count) {
    return t(
      count == 1 ? 'plan.activities_label.one' : 'plan.activities_label.other',
      params: {'count': '$count'},
    );
  }

  String memberCountLabel(int count) {
    return t('groups.member_count', params: {'count': '$count'});
  }

  String durationDaysLabel(int count) {
    return t(
      count == 1 ? 'plan.duration_days.one' : 'plan.duration_days.other',
      params: {'count': '$count'},
    );
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocaleStore.supportedLocales.any(
    (supported) => supported.languageCode == locale.languageCode,
  );

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(AppLocalizations(locale));
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationsContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
