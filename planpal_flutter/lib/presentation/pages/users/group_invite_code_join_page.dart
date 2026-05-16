import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_localizations.dart';
import '../../../core/riverpod/group_invite_providers.dart';
import '../../../core/services/api_error.dart';
import '../../../core/services/error_display_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/ui_states/ui_states.dart';
import 'group_details_page.dart';

class GroupInviteCodeJoinPage extends ConsumerStatefulWidget {
  const GroupInviteCodeJoinPage({super.key});

  @override
  ConsumerState<GroupInviteCodeJoinPage> createState() =>
      _GroupInviteCodeJoinPageState();
}

class _GroupInviteCodeJoinPageState
    extends ConsumerState<GroupInviteCodeJoinPage> {
  final TextEditingController _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      ErrorDisplayService.showErrorSnackbar(
        context,
        context.l10n.t('group_join.invalid_code'),
      );
      return;
    }

    final result = await ref.read(joinGroupProvider.notifier).joinCode(code);
    if (!mounted) return;
    if (result == null) {
      final error = ref.read(joinGroupProvider).error;
      if (error != null) {
        if (_isAlreadyMemberError(error)) {
          ErrorDisplayService.showWarningSnackbar(
            context,
            context.l10n.t('group_join.already_member'),
          );
          return;
        }
        ErrorDisplayService.handleError(context, error);
      }
    }
  }

  bool _isAlreadyMemberError(Object error) {
    if (error is! ApiException) return false;
    final data = error.data;
    if (data is! Map) return false;
    final code = data['error_code'] ?? data['code'];
    return code?.toString() == 'already_member';
  }

  @override
  Widget build(BuildContext context) {
    final joinState = ref.watch(joinGroupProvider);
    final result = joinState.valueOrNull;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.t('group_join.title'))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: joinState.isLoading
                  ? AppLoading(
                      message: context.l10n.t('group_join.checking_code'),
                    )
                  : result != null
                  ? _JoinResult(result: result)
                  : Column(
                      key: const ValueKey('code-input'),
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(
                          Icons.password_rounded,
                          color: colorScheme.primary,
                          size: 64,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          context.l10n.t('group_join.enter_code'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.l10n.t('group_join.description'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: _codeController,
                          autofocus: true,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          maxLength: 6,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(6),
                          ],
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 10,
                              ),
                          decoration: const InputDecoration(
                            counterText: '',
                            hintText: '000000',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _join(),
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _join,
                          icon: const Icon(Icons.login_rounded),
                          label: Text(context.l10n.t('group_join.join_action')),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _JoinResult extends StatelessWidget {
  final dynamic result;

  const _JoinResult({required this.result});

  @override
  Widget build(BuildContext context) {
    final isPending = result.status == 'pending';
    return Column(
      key: const ValueKey('result'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          isPending ? Icons.hourglass_top_rounded : Icons.check_circle_rounded,
          color: isPending ? Colors.orange : AppColors.success,
          size: 64,
        ),
        const SizedBox(height: 16),
        Text(
          isPending
              ? context.l10n.t('group_join.request_sent')
              : context.l10n.t('group_join.joined_successfully'),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(result.message, textAlign: TextAlign.center),
        const SizedBox(height: 24),
        if (!isPending)
          FilledButton(
            onPressed: () => Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => GroupDetailsPage(id: result.group.id),
              ),
            ),
            child: Text(context.l10n.t('group_join.open_group')),
          )
        else
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.t('common.done')),
          ),
      ],
    );
  }
}
