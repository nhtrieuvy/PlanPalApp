import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/dtos/group_invite_model.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/riverpod/group_invite_providers.dart';
import '../../../core/services/error_display_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/ui_states/ui_states.dart';

class GroupInviteManagementPage extends ConsumerWidget {
  final String groupId;
  final String groupName;
  final String groupVisibility;

  const GroupInviteManagementPage({
    super.key,
    required this.groupId,
    required this.groupName,
    this.groupVisibility = 'private',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invitesState = ref.watch(groupInvitesProvider(groupId));
    final requestsState = ref.watch(groupJoinRequestsProvider(groupId));
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('group_invites.title')),
        actions: [
          IconButton(
            onPressed: () => _showCreateInviteSheet(context, ref),
            icon: const Icon(Icons.add_rounded),
            tooltip: l10n.t('group_invites.create_code'),
          ),
        ],
      ),
      body: invitesState.when(
        loading: () => AppLoading(message: l10n.t('group_invites.loading')),
        error: (error, _) => AppError(
          message: l10n.t('group_invites.load_error'),
          onRetry: () => ref.invalidate(groupInvitesProvider(groupId)),
        ),
        data: (invites) {
          final shouldShowRequests = groupVisibility == 'private';
          final shouldShowEmptyState = invites.isEmpty;
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(groupInvitesProvider(groupId));
              ref.invalidate(groupJoinRequestsProvider(groupId));
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount:
                  invites.length +
                  (shouldShowEmptyState ? 1 : 0) +
                  (shouldShowRequests ? 1 : 0),
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                if (shouldShowEmptyState && index == 0) {
                  return _EmptyInvites(
                    onCreate: () => _showCreateInviteSheet(context, ref),
                  );
                }
                final inviteIndex = shouldShowEmptyState ? index - 1 : index;
                if (inviteIndex >= 0 && inviteIndex < invites.length) {
                  final invite = invites[inviteIndex];
                  return _InviteCard(
                    invite: invite,
                    onCopy: () => _copyInvite(context, invite),
                    onShare: () => _shareInvite(context, invite),
                    onRevoke: () => _revokeInvite(context, ref, invite),
                  );
                }
                return _JoinRequestsCard(
                  state: requestsState,
                  onRetry: () =>
                      ref.invalidate(groupJoinRequestsProvider(groupId)),
                  onApprove: (requestId) =>
                      _approveJoinRequest(context, ref, requestId),
                  onReject: (requestId) =>
                      _rejectJoinRequest(context, ref, requestId),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _showCreateInviteSheet(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final result = await showModalBottomSheet<CreateGroupInviteRequest>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => _CreateInviteSheet(
        groupName: groupName,
        groupVisibility: groupVisibility,
      ),
    );
    if (result == null || !context.mounted) return;

    try {
      final created = await ref
          .read(groupInvitesProvider(groupId).notifier)
          .createInvite(result);
      if (!context.mounted || created == null) return;
      ErrorDisplayService.showSuccessSnackbar(
        context,
        context.l10n.t('group_invites.created_success'),
      );
      _shareInvite(context, created);
    } catch (error) {
      if (context.mounted) ErrorDisplayService.handleError(context, error);
    }
  }

  Future<void> _copyInvite(
    BuildContext context,
    GroupInviteModel invite,
  ) async {
    await Clipboard.setData(ClipboardData(text: invite.inviteCode));
    if (!context.mounted) return;
    ErrorDisplayService.showSuccessSnackbar(
      context,
      context.l10n.t('group_invites.copied_success'),
    );
  }

  Future<void> _shareInvite(
    BuildContext context,
    GroupInviteModel invite,
  ) async {
    await Share.share(
      context.l10n.t(
        'group_invites.share_text',
        params: {'group': groupName, 'code': invite.inviteCode},
      ),
    );
  }

  Future<void> _revokeInvite(
    BuildContext context,
    WidgetRef ref,
    GroupInviteModel invite,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.l10n.t('group_invites.revoke_title')),
        content: Text(context.l10n.t('group_invites.revoke_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.t('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(context.l10n.t('common.revoke')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(groupInvitesProvider(groupId).notifier)
          .revokeInvite(invite.id);
      if (context.mounted) {
        ErrorDisplayService.showSuccessSnackbar(
          context,
          context.l10n.t('group_invites.revoked_success'),
        );
      }
    } catch (error) {
      if (context.mounted) ErrorDisplayService.handleError(context, error);
    }
  }

  Future<void> _approveJoinRequest(
    BuildContext context,
    WidgetRef ref,
    String requestId,
  ) async {
    try {
      await ref
          .read(groupJoinRequestsProvider(groupId).notifier)
          .approve(requestId);
      if (context.mounted) {
        ErrorDisplayService.showSuccessSnackbar(
          context,
          context.l10n.t('group_invites.request_approved'),
        );
      }
    } catch (error) {
      if (context.mounted) ErrorDisplayService.handleError(context, error);
    }
  }

  Future<void> _rejectJoinRequest(
    BuildContext context,
    WidgetRef ref,
    String requestId,
  ) async {
    try {
      await ref
          .read(groupJoinRequestsProvider(groupId).notifier)
          .reject(requestId);
      if (context.mounted) {
        ErrorDisplayService.showSuccessSnackbar(
          context,
          context.l10n.t('group_invites.request_rejected'),
        );
      }
    } catch (error) {
      if (context.mounted) ErrorDisplayService.handleError(context, error);
    }
  }
}

class _EmptyInvites extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyInvites({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.password_rounded, size: 64, color: Colors.grey.shade500),
            const SizedBox(height: 16),
            Text(
              l10n.t('group_invites.empty_title'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.t('group_invites.empty_description'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.password_rounded),
              label: Text(l10n.t('group_invites.create_code')),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateInviteSheet extends StatefulWidget {
  final String groupName;
  final String groupVisibility;

  const _CreateInviteSheet({
    required this.groupName,
    required this.groupVisibility,
  });

  @override
  State<_CreateInviteSheet> createState() => _CreateInviteSheetState();
}

class _CreateInviteSheetState extends State<_CreateInviteSheet> {
  final TextEditingController _maxUsesController = TextEditingController();
  int _expiryDays = 7;

  @override
  void dispose() {
    _maxUsesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.t('group_invites.create_sheet_title'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              widget.groupVisibility == 'public'
                  ? l10n.t(
                      'group_invites.public_help',
                      params: {'group': widget.groupName},
                    )
                  : l10n.t(
                      'group_invites.private_help',
                      params: {'group': widget.groupName},
                    ),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            Text(
              l10n.t('group_invites.expiration'),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('1d')),
                ButtonSegment(value: 7, label: Text('7d')),
                ButtonSegment(value: 30, label: Text('30d')),
              ],
              selected: {_expiryDays},
              onSelectionChanged: (value) {
                setState(() => _expiryDays = value.first);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _maxUsesController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.t('group_invites.usage_limit'),
                hintText: l10n.t('group_invites.usage_limit_hint'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  final maxUses = int.tryParse(_maxUsesController.text.trim());
                  Navigator.of(context).pop(
                    CreateGroupInviteRequest(
                      expiresAt: DateTime.now().add(
                        Duration(days: _expiryDays),
                      ),
                      maxUses: maxUses,
                    ),
                  );
                },
                icon: const Icon(Icons.password_rounded),
                label: Text(l10n.t('group_invites.generate_code')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  final GroupInviteModel invite;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onRevoke;

  const _InviteCard({
    required this.invite,
    required this.onCopy,
    required this.onShare,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('dd/MM/yyyy HH:mm');
    final statusColor = invite.isUsable ? AppColors.success : Colors.red;
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.password_rounded, color: statusColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    invite.isUsable
                        ? l10n.t('group_invites.active_code')
                        : l10n.t('group_invites.inactive_code'),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Chip(
                  label: Text(
                    invite.isUsable
                        ? l10n.t('group_invites.active')
                        : l10n.t('group_invites.closed'),
                  ),
                  backgroundColor: statusColor.withValues(alpha: 0.12),
                  labelStyle: TextStyle(color: statusColor),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText(
              invite.inviteCode,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 6,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _MetaPill(
                  icon: Icons.timer_outlined,
                  text: invite.expiresAt == null
                      ? l10n.t('group_invites.no_expiry')
                      : l10n.t(
                          'group_invites.expires_at',
                          params: {
                            'date': formatter.format(
                              invite.expiresAt!.toLocal(),
                            ),
                          },
                        ),
                ),
                _MetaPill(
                  icon: Icons.people_outline,
                  text: invite.maxUses == null
                      ? l10n.t(
                          'group_invites.joined_count',
                          params: {'count': '${invite.currentUses}'},
                        )
                      : l10n.t(
                          'group_invites.used_count',
                          params: {
                            'current': '${invite.currentUses}',
                            'max': '${invite.maxUses}',
                          },
                        ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy),
                  label: Text(l10n.t('common.copy')),
                ),
                TextButton.icon(
                  onPressed: onShare,
                  icon: const Icon(Icons.ios_share),
                  label: Text(l10n.t('common.share')),
                ),
                const Spacer(),
                if (invite.isActive)
                  TextButton.icon(
                    onPressed: onRevoke,
                    icon: const Icon(Icons.block),
                    label: Text(l10n.t('common.revoke')),
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinRequestsCard extends StatelessWidget {
  final AsyncValue<List<GroupJoinRequestModel>> state;
  final VoidCallback onRetry;
  final ValueChanged<String> onApprove;
  final ValueChanged<String> onReject;

  const _JoinRequestsCard({
    required this.state,
    required this.onRetry,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: state.when(
          loading: () =>
              AppLoading(message: l10n.t('group_invites.loading_requests')),
          error: (_, __) => AppError(
            message: l10n.t('group_invites.load_requests_error'),
            onRetry: onRetry,
          ),
          data: (requests) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.how_to_reg),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.t('group_invites.pending_requests'),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Chip(label: Text('${requests.length}')),
                  ],
                ),
                const SizedBox(height: 12),
                if (requests.isEmpty)
                  Text(
                    l10n.t('group_invites.no_pending_requests'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  )
                else
                  ...requests.map(
                    (request) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        child: Text(
                          request.user.initials.isNotEmpty
                              ? request.user.initials
                              : '?',
                        ),
                      ),
                      title: Text(
                        request.user.fullName.isNotEmpty
                            ? request.user.fullName
                            : request.user.username,
                      ),
                      subtitle: Text(
                        l10n.t(
                          'group_invites.requested_at',
                          params: {
                            'date': DateFormat(
                              'dd/MM/yyyy HH:mm',
                            ).format(request.createdAt.toLocal()),
                          },
                        ),
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: l10n.t('group_invites.reject'),
                            icon: const Icon(Icons.close),
                            color: Colors.red,
                            onPressed: () => onReject(request.id),
                          ),
                          IconButton(
                            tooltip: l10n.t('group_invites.approve'),
                            icon: const Icon(Icons.check),
                            color: AppColors.success,
                            onPressed: () => onApprove(request.id),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MetaPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(text, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
