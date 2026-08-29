import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:planpal_flutter/core/dtos/group_model.dart';
import 'package:planpal_flutter/core/dtos/group_requests.dart';
import 'package:planpal_flutter/core/dtos/user_summary.dart';
import 'package:planpal_flutter/core/localization/app_localizations.dart';
import 'package:planpal_flutter/core/repositories/friend_repository.dart';
import 'package:planpal_flutter/core/repositories/group_repository.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/services/error_display_service.dart';
import 'package:planpal_flutter/presentation/widgets/forms/form_wizard_scaffold.dart';

class GroupFormPage extends ConsumerStatefulWidget {
  final Map<String, dynamic>? initial;

  const GroupFormPage({super.key, this.initial});

  @override
  ConsumerState<GroupFormPage> createState() => _GroupFormPageState();
}

class _GroupFormPageState extends ConsumerState<GroupFormPage> {
  final _basicStepKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  bool _submitting = false;
  File? _avatarFile;
  File? _coverFile;
  String _visibility = 'private';
  List<UserSummary> _availableFriends = [];
  final Set<UserSummary> _selectedMembers = {};
  bool _loadingFriends = false;
  int _currentStep = 0;

  GroupRepository get _repo => ref.read(groupRepositoryProvider);
  FriendRepository get _friendRepo => ref.read(friendRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
      text: widget.initial?['name']?.toString() ?? '',
    );
    _descCtrl = TextEditingController(
      text: widget.initial?['description']?.toString() ?? '',
    );
    _visibility = widget.initial?['visibility']?.toString() ?? 'private';

    if (widget.initial == null) {
      _loadFriends();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    setState(() => _loadingFriends = true);
    try {
      final friends = await _friendRepo.getFriends();
      setState(() {
        _availableFriends = friends;
        _loadingFriends = false;
      });
    } catch (error) {
      setState(() => _loadingFriends = false);
      if (mounted) {
        ErrorDisplayService.handleError(context, error);
      }
    }
  }

  Future<void> _submit() async {
    if (!_validateBeforeSubmit()) return;

    setState(() => _submitting = true);
    try {
      GroupModel result;
      if (widget.initial == null) {
        final request = CreateGroupRequest(
          name: _nameCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          visibility: _visibility,
          initialMembers: _selectedMembers.map((member) => member.id).toList(),
        );
        result = await _repo.createGroup(
          request,
          avatar: _avatarFile,
          coverImage: _coverFile,
        );
        if (!mounted) return;
        _evictGroupImages(result);
        Navigator.of(context).pop({
          'action': 'created',
          'group': {
            'id': result.id,
            'name': result.name,
            'description': result.description,
            'visibility': result.visibility,
            'avatar_thumb': result.avatarUrl,
            'cover_image_url': result.coverImageUrl,
            'member_count': result.memberCount,
          },
        });
      } else {
        final request = UpdateGroupRequest(
          name: _nameCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          visibility: _visibility,
        );
        result = await _repo.updateGroup(
          widget.initial!['id'] as String,
          request,
          avatar: _avatarFile,
          coverImage: _coverFile,
        );
        if (!mounted) return;
        _evictGroupImages(result);
        Navigator.of(context).pop({
          'action': 'updated',
          'group': {
            'id': result.id,
            'name': result.name,
            'description': result.description,
            'visibility': result.visibility,
            'avatar_thumb': result.avatarUrl,
            'cover_image_url': result.coverImageUrl,
            'member_count': result.memberCount,
          },
        });
      }
    } catch (error) {
      if (!mounted) return;
      ErrorDisplayService.handleError(context, error, showDialog: true);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _evictGroupImages(GroupModel group) {
    try {
      if (group.avatarUrl.isNotEmpty) {
        CachedNetworkImage.evictFromCache(group.avatarUrl);
      }
      if (group.coverImageUrl.isNotEmpty) {
        CachedNetworkImage.evictFromCache(group.coverImageUrl);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isEdit = widget.initial != null;

    return FormWizardScaffold(
      title: isEdit
          ? l10n.t('group_form.title_edit')
          : l10n.t('group_form.title_create'),
      steps: _buildWizardSteps(context),
      currentStep: _currentStep,
      isSubmitting: _submitting,
      onBack: _handleBack,
      onNext: _handleNext,
      onFinish: _submit,
    );
  }

  List<FormWizardStep> _buildWizardSteps(BuildContext context) {
    final l10n = context.l10n;
    final isEdit = widget.initial != null;
    return [
      FormWizardStep(
        title: l10n.t('wizard.basic_info'),
        icon: Icons.groups_outlined,
        child: Form(key: _basicStepKey, child: _buildBasicStep(context)),
      ),
      FormWizardStep(
        title: l10n.t('wizard.media'),
        icon: Icons.photo_library_outlined,
        child: _buildMediaStep(context),
      ),
      FormWizardStep(
        title: l10n.t('group_form.access_title'),
        icon: Icons.shield_outlined,
        child: _buildAccessStep(context, isEdit: isEdit),
      ),
      FormWizardStep(
        title: l10n.t('wizard.review'),
        icon: Icons.fact_check_outlined,
        subtitle: l10n.t('wizard.review_subtitle'),
        child: _buildReviewStep(context, isEdit: isEdit),
      ),
    ];
  }

  void _handleBack() {
    if (_currentStep == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _currentStep -= 1);
  }

  void _handleNext() {
    if (!_validateCurrentStep()) return;
    setState(() => _currentStep += 1);
  }

  bool _validateCurrentStep() {
    if (_currentStep == 0) {
      return _basicStepKey.currentState?.validate() ?? _validateBasicDraft();
    }
    if (_currentStep == 2 &&
        widget.initial == null &&
        _selectedMembers.length < 2) {
      ErrorDisplayService.showWarningSnackbar(
        context,
        context.l10n.t('group_form.members_requirement'),
      );
      return false;
    }
    return true;
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return context.l10n.t('group_form.name_required');
    }
    return null;
  }

  bool _validateBasicDraft({bool redirectToStep = false}) {
    final error = _validateName(_nameCtrl.text);
    if (error == null) return true;

    if (redirectToStep && _currentStep != 0) {
      setState(() => _currentStep = 0);
    }
    ErrorDisplayService.showErrorSnackbar(context, error);
    return false;
  }

  bool _validateBeforeSubmit() {
    if (!_validateBasicDraft(redirectToStep: true)) {
      return false;
    }
    if (widget.initial == null && _selectedMembers.length < 2) {
      setState(() => _currentStep = 2);
      ErrorDisplayService.showWarningSnackbar(
        context,
        context.l10n.t('group_form.members_requirement'),
      );
      return false;
    }
    return true;
  }

  Widget _buildBasicStep(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        TextFormField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            labelText: l10n.t('group_form.name_label'),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.group_outlined),
          ),
          validator: _validateName,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _descCtrl,
          decoration: InputDecoration(
            labelText: l10n.t('group_form.description_label'),
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.notes_outlined),
          ),
          maxLines: 4,
        ),
      ],
    );
  }

  Widget _buildMediaStep(BuildContext context) {
    final l10n = context.l10n;
    final isEdit = widget.initial != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.t('group_form.avatar_title'),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Center(child: _buildAvatarPicker(isEdit)),
        if (isEdit) ...[
          const SizedBox(height: 24),
          Text(
            l10n.t('group_form.cover_title'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _buildCoverPicker(),
        ],
      ],
    );
  }

  Widget _buildAccessStep(BuildContext context, {required bool isEdit}) {
    return Column(
      children: [
        _buildVisibilitySelector(),
        if (!isEdit) ...[const SizedBox(height: 20), _buildMemberSelection()],
      ],
    );
  }

  Widget _buildReviewStep(BuildContext context, {required bool isEdit}) {
    final l10n = context.l10n;
    return Column(
      children: [
        ReviewSection(
          title: l10n.t('wizard.basic_info'),
          items: [
            ReviewItem(l10n.t('group_form.name_label'), _nameCtrl.text),
            ReviewItem(l10n.t('group_form.description_label'), _descCtrl.text),
          ],
        ),
        const SizedBox(height: 12),
        ReviewSection(
          title: l10n.t('group_form.access_title'),
          items: [
            ReviewItem(
              l10n.t('group_form.access_title'),
              _visibility == 'public'
                  ? l10n.t('plan.public')
                  : l10n.t('plan.private'),
            ),
            if (!isEdit)
              ReviewItem(
                l10n.t('group_form.members_title'),
                '${_selectedMembers.length}',
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildAvatarPicker(bool isEdit) {
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () async {
        final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 300,
          maxHeight: 300,
          imageQuality: 85,
        );
        if (picked != null) {
          setState(() {
            _avatarFile = File(picked.path);
          });
        }
      },
      child: CircleAvatar(
        radius: 40,
        backgroundColor: colorScheme.surfaceContainerHighest,
        child: _avatarFile != null
            ? ClipOval(
                child: Image.file(
                  _avatarFile!,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                ),
              )
            : (isEdit && widget.initial != null)
            ? (() {
                final url =
                    (widget.initial!['avatar_url'] ??
                            widget.initial!['avatar_thumb'])
                        ?.toString();
                if (url != null && url.isNotEmpty) {
                  return ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: url,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          Icon(
                            Icons.group,
                            size: 40,
                            color: colorScheme.onSurfaceVariant,
                          ),
                      errorWidget: (context, url, error) =>
                          Icon(
                            Icons.group,
                            size: 40,
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  );
                }
                return Icon(
                  Icons.group,
                  size: 40,
                  color: colorScheme.onSurfaceVariant,
                );
              })()
            : Icon(
                Icons.group,
                size: 40,
                color: colorScheme.onSurfaceVariant,
              ),
      ),
    );
  }

  Widget _buildCoverPicker() {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () async {
        final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 1200,
          maxHeight: 400,
          imageQuality: 85,
        );
        if (picked != null) {
          setState(() {
            _coverFile = File(picked.path);
          });
        }
      },
      child: Container(
        width: double.infinity,
        height: 120,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: _coverFile != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(_coverFile!, fit: BoxFit.cover),
              )
            : (widget.initial?['cover_image_url'] != null &&
                  widget.initial!['cover_image_url'].toString().isNotEmpty)
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: widget.initial!['cover_image_url'],
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.landscape,
                        size: 40,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.t('group_form.cover_loading'),
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  errorWidget: (context, url, error) => Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.landscape,
                        size: 40,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.t('group_form.cover_pick'),
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.landscape,
                    size: 40,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.t('group_form.cover_pick'),
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildVisibilitySelector() {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.t('group_form.access_title'),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'private',
                icon: const Icon(Icons.lock_outline),
                label: Text(l10n.t('plan.private')),
              ),
              ButtonSegment(
                value: 'public',
                icon: const Icon(Icons.public),
                label: Text(l10n.t('plan.public')),
              ),
            ],
            selected: {_visibility},
            onSelectionChanged: (value) {
              setState(() => _visibility = value.first);
            },
          ),
          const SizedBox(height: 8),
          Text(
            _visibility == 'public'
                ? l10n.t('group_form.public_join_description')
                : l10n.t('group_form.private_join_description'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberSelection() {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.t('group_form.members_title'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _selectedMembers.length < 2
                    ? colorScheme.errorContainer
                    : colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedMembers.length < 2
                      ? colorScheme.error
                      : colorScheme.tertiary,
                ),
              ),
              child: Text(
                '${_selectedMembers.length}/∞',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _selectedMembers.length < 2
                      ? colorScheme.onErrorContainer
                      : colorScheme.onTertiaryContainer,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l10n.t('group_form.members_requirement'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        if (_loadingFriends)
          const Center(child: CircularProgressIndicator())
        else if (_availableFriends.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Center(child: Text(l10n.t('group_form.no_friends'))),
          )
        else
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              border: Border.all(color: colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _availableFriends.length,
              itemBuilder: (context, index) {
                final friend = _availableFriends[index];
                final isSelected = _selectedMembers.any(
                  (member) => member.id == friend.id,
                );
                return CheckboxListTile(
                  value: isSelected,
                  onChanged: (checked) {
                    setState(() {
                      if (checked == true) {
                        _selectedMembers.add(friend);
                      } else {
                        _selectedMembers.removeWhere(
                          (member) => member.id == friend.id,
                        );
                      }
                    });
                  },
                  title: Text(friend.fullName),
                  subtitle: Text('@${friend.username}'),
                  secondary: CircleAvatar(
                    backgroundImage: friend.avatarUrl?.isNotEmpty == true
                        ? CachedNetworkImageProvider(friend.avatarUrl!)
                        : null,
                    child: friend.avatarUrl?.isEmpty != false
                        ? Text(friend.initials)
                        : null,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}
