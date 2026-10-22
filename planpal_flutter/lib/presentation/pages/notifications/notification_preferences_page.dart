import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/notification_model.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/notifications_provider.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/core/services/firebase_runtime_config.dart';
import 'package:planpal_flutter/core/services/firebase_service.dart';
import 'package:planpal_flutter/presentation/widgets/layout/responsive_content.dart';
import 'package:planpal_flutter/shared/ui_states/ui_states.dart';

class NotificationPreferencesPage extends ConsumerStatefulWidget {
  const NotificationPreferencesPage({super.key});

  @override
  ConsumerState<NotificationPreferencesPage> createState() =>
      _NotificationPreferencesPageState();
}

class _NotificationPreferencesPageState
    extends ConsumerState<NotificationPreferencesPage> {
  NotificationPreferenceModel? _draft;
  bool _saving = false;
  bool _enablingWebPush = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(notificationPreferencesProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.t('notification_settings.title')),
      ),
      body: async.when(
        loading: () => const AppSkeleton.list(itemCount: 4),
        error: (error, _) => AppError(
          message: ErrorDisplayService.getUserFriendlyMessage(error),
          onRetry: () => ref.invalidate(notificationPreferencesProvider),
          retryLabel: context.l10n.t('common.retry'),
        ),
        data: (value) {
          _draft ??= value;
          return ResponsiveContent(
            mediumMaxWidth: 680,
            expandedMaxWidth: 760,
            child: _buildForm(_draft!),
          );
        },
      ),
    );
  }

  Widget _buildForm(NotificationPreferenceModel value) {
    final theme = Theme.of(context);
    final webPushEnabled = FirebaseService.instance.currentToken != null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (kIsWeb) ...[
          Card(
            child: ListTile(
              leading: const Icon(Icons.install_desktop_outlined),
              title: Text(
                context.l10n.t('notification_settings.web_push_title'),
              ),
              subtitle: Text(
                context.l10n.t('notification_settings.web_push_hint'),
              ),
              trailing: FilledButton(
                onPressed: _enablingWebPush || webPushEnabled
                    ? null
                    : _enableWebPush,
                child: _enablingWebPush
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        context.l10n.t(
                          webPushEnabled
                              ? 'notification_settings.web_push_active'
                              : 'notification_settings.web_push_enable',
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Card(
          child: Column(
            children: [
              SwitchListTile.adaptive(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: Text(context.l10n.t('notification_settings.push')),
                subtitle: Text(
                  context.l10n.t('notification_settings.push_hint'),
                ),
                value: value.pushEnabled,
                onChanged: (next) => _change(value.copyWith(pushEnabled: next)),
              ),
              const Divider(height: 1),
              SwitchListTile.adaptive(
                secondary: const Icon(Icons.bedtime_outlined),
                title: Text(context.l10n.t('notification_settings.quiet')),
                subtitle: Text(
                  context.l10n.t('notification_settings.quiet_hint'),
                ),
                value: value.quietHoursEnabled,
                onChanged: (next) => _change(
                  value.copyWith(
                    quietHoursEnabled: next,
                    quietHoursStart: value.quietHoursStart ?? '22:00:00',
                    quietHoursEnd: value.quietHoursEnd ?? '07:00:00',
                  ),
                ),
              ),
              if (value.quietHoursEnabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: _TimeCard(
                          label: context.l10n.t('notification_settings.from'),
                          value: value.quietHoursStart ?? '22:00:00',
                          onTap: () => _pickTime(true),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TimeCard(
                          label: context.l10n.t('notification_settings.to'),
                          value: value.quietHoursEnd ?? '07:00:00',
                          onTap: () => _pickTime(false),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              SwitchListTile.adaptive(
                secondary: const Icon(Icons.summarize_outlined),
                title: Text(context.l10n.t('notification_settings.digest')),
                subtitle: Text(
                  context.l10n.t('notification_settings.digest_hint'),
                ),
                value: value.dailyDigestEnabled,
                onChanged: (next) =>
                    _change(value.copyWith(dailyDigestEnabled: next)),
              ),
              if (value.dailyDigestEnabled)
                ListTile(
                  leading: const Icon(Icons.schedule_outlined),
                  title: Text(
                    context.l10n.t('notification_settings.digest_time'),
                  ),
                  trailing: Text(
                    '${value.dailyDigestHour.toString().padLeft(2, '0')}:00',
                    style: theme.textTheme.titleMedium,
                  ),
                  onTap: _pickDigestHour,
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(context.l10n.t('common.save')),
        ),
      ],
    );
  }

  void _change(NotificationPreferenceModel value) {
    setState(() => _draft = value);
  }

  Future<void> _pickTime(bool start) async {
    final current = start ? _draft!.quietHoursStart : _draft!.quietHoursEnd;
    final parts = (current ?? '00:00').split(':');
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 0,
        minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      ),
    );
    if (selected == null || !mounted) return;
    final formatted =
        '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}:00';
    _change(
      start
          ? _draft!.copyWith(quietHoursStart: formatted)
          : _draft!.copyWith(quietHoursEnd: formatted),
    );
  }

  Future<void> _pickDigestHour() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _draft!.dailyDigestHour, minute: 0),
    );
    if (selected != null && mounted) {
      _change(_draft!.copyWith(dailyDigestHour: selected.hour));
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(notificationRepositoryProvider)
          .updatePreferences(_draft!);
      if (!mounted) return;
      setState(() => _draft = saved);
      ref.invalidate(notificationPreferencesProvider);
      ErrorDisplayService.showSuccessSnackbar(
        context,
        context.l10n.t('notification_settings.saved'),
      );
    } catch (error) {
      if (mounted) {
        ErrorDisplayService.showErrorSnackbar(
          context,
          ErrorDisplayService.getUserFriendlyMessage(error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _enableWebPush() async {
    if (!FirebaseRuntimeConfig.webPushConfigured) {
      ErrorDisplayService.showErrorSnackbar(
        context,
        context.l10n.t('notification_settings.web_push_not_configured'),
      );
      return;
    }
    final token = ref.read(authNotifierProvider).token;
    if (token == null) return;
    setState(() => _enablingWebPush = true);
    try {
      final registered = await FirebaseService.instance.registerToken(token);
      if (!mounted) return;
      if (registered) {
        ErrorDisplayService.showSuccessSnackbar(
          context,
          context.l10n.t('notification_settings.web_push_enabled'),
        );
      } else {
        ErrorDisplayService.showErrorSnackbar(
          context,
          context.l10n.t('notification_settings.web_push_denied'),
        );
      }
    } catch (_) {
      if (mounted) {
        ErrorDisplayService.showErrorSnackbar(
          context,
          context.l10n.t('notification_settings.web_push_failed'),
        );
      }
    } finally {
      if (mounted) setState(() => _enablingWebPush = false);
    }
  }
}

class _TimeCard extends StatelessWidget {
  const _TimeCard({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    child: Column(children: [Text(label), Text(value.substring(0, 5))]),
  );
}
