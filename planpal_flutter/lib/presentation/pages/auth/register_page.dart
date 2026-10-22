import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:planpal_flutter/core/theme/app_design_tokens.dart';
import 'package:planpal_flutter/presentation/pages/auth/auth_journey_shell.dart';
import 'package:planpal_flutter/presentation/pages/auth/email_verification_page.dart';
import 'package:planpal_flutter/presentation/widgets/common/x_file_image.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _isLoading = false;
  int _currentStep = 0;
  XFile? _avatarImage;
  final ImagePicker _picker = ImagePicker();

  @override
  void dispose() {
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final l10n = context.l10n;
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _avatarImage = image;
        });
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.t(
              'auth.pick_image_error',
              params: {'error': l10n.t('chat.pick_image_failed')},
            ),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = context.l10n;

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(userRepositoryProvider);
      final email = _emailController.text.trim();

      await repo.register(
        username: _usernameController.text.trim(),
        email: email,
        password: _passwordController.text,
        passwordConfirm: _confirmPasswordController.text,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        avatar: _avatarImage,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.t('auth.register_verify_email')),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context, rootNavigator: true).pushReplacement(
        MaterialPageRoute(builder: (_) => EmailVerificationPage(email: email)),
      );
    } catch (e) {
      if (!mounted) return;
      ErrorDisplayService.handleError(context, e);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      AuthFormViewport(child: _buildRegistrationForm(context));

  Widget _buildRegistrationForm(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.t('auth.register_title'),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.t(
                'auth.step_progress',
                params: {'current': '${_currentStep + 1}', 'total': '3'},
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            LinearProgressIndicator(value: (_currentStep + 1) / 3),
            const SizedBox(height: AppSpacing.xl),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: KeyedSubtree(
                key: ValueKey(_currentStep),
                child: _buildCurrentStep(context),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                if (_currentStep > 0) ...[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading
                          ? null
                          : () => setState(() => _currentStep--),
                      child: Text(l10n.t('wizard.back')),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: FilledButton(
                    onPressed: _isLoading ? null : _handlePrimaryAction,
                    child: _isLoading
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _currentStep == 2
                                ? l10n.t('auth.register')
                                : l10n.t('wizard.next'),
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: _isLoading
                  ? null
                  : () => context.go(authSwitchLocation(context, '/login')),
              child: Text(
                '${l10n.t('auth.have_account')} ${l10n.t('auth.login')}',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentStep(BuildContext context) {
    final l10n = context.l10n;
    if (_currentStep == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stepHeading(
            context,
            'auth.step_identity',
            'auth.step_identity_hint',
          ),
          _buildTextField(
            controller: _firstNameController,
            label: l10n.t('auth.first_name'),
            icon: Icons.badge_outlined,
            validator: (value) => value == null || value.trim().isEmpty
                ? l10n.t('auth.validation_first_name_required')
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          _buildTextField(
            controller: _lastNameController,
            label: l10n.t('auth.last_name'),
            icon: Icons.badge_outlined,
            validator: (value) => value == null || value.trim().isEmpty
                ? l10n.t('auth.validation_last_name_required')
                : null,
          ),
          const SizedBox(height: AppSpacing.md),
          _buildTextField(
            controller: _emailController,
            label: l10n.t('auth.email'),
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return l10n.t('auth.validation_email_required');
              }
              if (!RegExp(
                r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
              ).hasMatch(value.trim())) {
                return l10n.t('auth.validation_email_invalid');
              }
              return null;
            },
          ),
        ],
      );
    }
    if (_currentStep == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _stepHeading(context, 'auth.step_account', 'auth.step_account_hint'),
          _buildTextField(
            controller: _usernameController,
            label: l10n.t('auth.username'),
            icon: Icons.person_outline,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return l10n.t('auth.validation_username_required');
              }
              return value.trim().length < 2
                  ? l10n.t('auth.validation_username_short')
                  : null;
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _buildPasswordField(
            controller: _passwordController,
            label: l10n.t('auth.password'),
            isVisible: _isPasswordVisible,
            onToggle: () =>
                setState(() => _isPasswordVisible = !_isPasswordVisible),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.t('auth.validation_password_required');
              }
              return value.length < 8
                  ? l10n.t('auth.validation_password_short')
                  : null;
            },
          ),
          const SizedBox(height: AppSpacing.md),
          _buildPasswordField(
            controller: _confirmPasswordController,
            label: l10n.t('auth.confirm_password'),
            isVisible: _isConfirmPasswordVisible,
            onToggle: () => setState(
              () => _isConfirmPasswordVisible = !_isConfirmPasswordVisible,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return l10n.t('auth.validation_confirm_password_required');
              }
              return value != _passwordController.text
                  ? l10n.t('auth.validation_confirm_password_mismatch')
                  : null;
            },
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stepHeading(context, 'auth.step_profile', 'auth.step_profile_hint'),
        Center(
          child: Semantics(
            button: true,
            label: l10n.t('auth.add_photo'),
            child: InkWell(
              onTap: _pickAvatar,
              borderRadius: BorderRadius.circular(60),
              child: CircleAvatar(
                radius: 50,
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: _avatarImage != null
                    ? ClipOval(
                        child: XFileImage(
                          file: _avatarImage!,
                          fit: BoxFit.cover,
                          width: 100,
                          height: 100,
                        ),
                      )
                    : const Icon(Icons.add_a_photo_outlined, size: 32),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildTextField(
          controller: _phoneController,
          label: l10n.t('auth.phone_optional'),
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          validator: (value) {
            if (value == null || value.trim().isEmpty) return null;
            final phone = value.trim();
            if (!RegExp(r'^[0-9+\-\s()]+$').hasMatch(phone)) {
              return l10n.t('auth.validation_phone_invalid');
            }
            final digits = phone.replaceAll(RegExp(r'\D'), '');
            return digits.length < 9 || digits.length > 15
                ? l10n.t('auth.validation_phone_length')
                : null;
          },
        ),
      ],
    );
  }

  Widget _stepHeading(BuildContext context, String titleKey, String hintKey) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.t(titleKey),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            context.l10n.t(hintKey),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  void _handlePrimaryAction() {
    if (!_formKey.currentState!.validate()) return;
    if (_currentStep < 2) {
      setState(() => _currentStep++);
      return;
    }
    _register();
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
      validator: validator,
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool isVisible,
    required VoidCallback onToggle,
    required String? Function(String?) validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: !isVisible,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          icon: Icon(isVisible ? Icons.visibility_off : Icons.visibility),
          onPressed: onToggle,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
      validator: validator,
    );
  }
}
