import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/core/theme/app_design_tokens.dart';
import 'package:planpal_flutter/presentation/widgets/design_system/journey_ui.dart';

class EmailVerificationPage extends ConsumerStatefulWidget {
  const EmailVerificationPage({super.key, required this.email});

  final String email;

  @override
  ConsumerState<EmailVerificationPage> createState() =>
      _EmailVerificationPageState();
}

class _EmailVerificationPageState extends ConsumerState<EmailVerificationPage> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  bool _isVerifying = false;
  bool _isResending = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = context.l10n;

    setState(() => _isVerifying = true);
    try {
      await ref
          .read(userRepositoryProvider)
          .verifyEmailCode(email: widget.email, code: _codeController.text);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.t('auth.verify_email_success')),
          backgroundColor: AppColors.success,
        ),
      );
      context.go('/login');
    } catch (e) {
      if (!mounted) return;
      ErrorDisplayService.handleError(context, e);
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resend() async {
    final l10n = context.l10n;

    setState(() => _isResending = true);
    try {
      await ref
          .read(userRepositoryProvider)
          .resendEmailVerification(email: widget.email);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.t('auth.verify_email_resend_success')),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ErrorDisplayService.handleError(context, e);
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: JourneySurface(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.mark_email_read_outlined,
                        size: 72,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        l10n.t('auth.verify_email_title'),
                        textAlign: TextAlign.center,
                        style: textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        l10n.t(
                          'auth.verify_email_subtitle',
                          params: {'email': widget.email},
                        ),
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      TextFormField(
                        controller: _codeController,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        textAlign: TextAlign.center,
                        style: textTheme.headlineMedium?.copyWith(
                          letterSpacing: 8,
                          fontWeight: FontWeight.w700,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: InputDecoration(
                          labelText: l10n.t('auth.verification_code'),
                          hintText: '000000',
                        ),
                        validator: (value) {
                          final code = (value ?? '').trim();
                          return code.length != 6
                              ? l10n.t('auth.verify_email_code_required')
                              : null;
                        },
                        onFieldSubmitted: (_) {
                          if (!_isVerifying) _verify();
                        },
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      SizedBox(
                        height: AppSize.controlHeight,
                        child: FilledButton(
                          onPressed: _isVerifying ? null : _verify,
                          child: _isVerifying
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(l10n.t('auth.verify_email_action')),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      TextButton(
                        onPressed: _isResending ? null : _resend,
                        child: Text(
                          _isResending
                              ? l10n.t('auth.resending_code')
                              : l10n.t('auth.resend_code'),
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.go('/login'),
                        child: Text(l10n.t('auth.back_to_login')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
