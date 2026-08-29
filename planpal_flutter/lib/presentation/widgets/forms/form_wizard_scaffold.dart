import 'package:flutter/material.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';

class FormWizardStep {
  final String title;
  final String? subtitle;
  final Widget child;
  final IconData? icon;

  const FormWizardStep({
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
  });
}

class FormWizardScaffold extends StatelessWidget {
  final List<FormWizardStep> steps;
  final int currentStep;
  final String title;
  final bool isSubmitting;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback? onFinish;

  const FormWizardScaffold({
    super.key,
    required this.steps,
    required this.currentStep,
    required this.title,
    required this.isSubmitting,
    this.onBack,
    this.onNext,
    this.onFinish,
  });

  bool get _isLastStep => currentStep == steps.length - 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final step = steps[currentStep];
    final progress = (currentStep + 1) / steps.length;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: AppBar(title: Text(title), centerTitle: true),
      body: SafeArea(
        child: Column(
          children: [
            _WizardHeader(
              step: step,
              currentStep: currentStep,
              totalSteps: steps.length,
              progress: progress,
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, _) => AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: SingleChildScrollView(
                    key: ValueKey(currentStep),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      20,
                      16,
                      20,
                      28 + MediaQuery.viewInsetsOf(context).bottom,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: _FormStepSurface(child: step.child),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _WizardActions(
              isSubmitting: isSubmitting,
              isLastStep: _isLastStep,
              onBack: onBack,
              onNext: onNext,
              onFinish: onFinish,
            ),
          ],
        ),
      ),
    );
  }
}

class _WizardHeader extends StatelessWidget {
  const _WizardHeader({
    required this.step,
    required this.currentStep,
    required this.totalSteps,
    required this.progress,
  });

  final FormWizardStep step;
  final int currentStep;
  final int totalSteps;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = context.l10n;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (step.icon != null) ...[
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(9),
                        child: Icon(
                          step.icon,
                          size: 20,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Text(
                      step.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    l10n.t(
                      'wizard.step_counter',
                      params: {
                        'current': '${currentStep + 1}',
                        'total': '$totalSteps',
                      },
                    ),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (step.subtitle != null) ...[
                const SizedBox(height: 5),
                Text(
                  step.subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 7,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormStepSurface extends StatelessWidget {
  const _FormStepSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _WizardActions extends StatelessWidget {
  const _WizardActions({
    required this.isSubmitting,
    required this.isLastStep,
    required this.onBack,
    required this.onNext,
    required this.onFinish,
  });

  final bool isSubmitting;
  final bool isLastStep;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback? onFinish;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isSubmitting ? null : onBack,
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: Text(l10n.t('wizard.back')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: isSubmitting
                      ? null
                      : (isLastStep ? onFinish : onNext),
                  icon: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          isLastStep
                              ? Icons.check_rounded
                              : Icons.arrow_forward_rounded,
                          size: 18,
                        ),
                  label: Text(
                    isLastStep
                        ? l10n.t('wizard.finish')
                        : l10n.t('wizard.next'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ReviewSection extends StatelessWidget {
  final String title;
  final List<ReviewItem> items;

  const ReviewSection({super.key, required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            ...items.map((item) => _ReviewRow(item: item)),
          ],
        ),
      ),
    );
  }
}

class ReviewItem {
  final String label;
  final String value;

  const ReviewItem(this.label, this.value);
}

class _ReviewRow extends StatelessWidget {
  final ReviewItem item;

  const _ReviewRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              item.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text(
              item.value.trim().isEmpty ? '-' : item.value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
