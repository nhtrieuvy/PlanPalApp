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
import 'package:planpal_flutter/core/theme/app_colors.dart';

class GroupFormPage extends ConsumerStatefulWidget {
  final Map<String, dynamic>? initial;

  const GroupFormPage({super.key, this.initial});

  @override
  ConsumerState<GroupFormPage> createState() => _GroupFormPageState();
}

class _GroupFormPageState extends ConsumerState<GroupFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  bool _submitting = false;
  File? _avatarFile;
  File? _coverFile;
  String _visibility = 'private';
  List<UserSummary> _availableFriends = [];
  final Set<UserSummary> _selectedMembers = {};
  bool _loadingFriends = false;

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
    final l10n = context.l10n;
    if (!_formKey.currentState!.validate()) return;

    if (widget.initial == null && _selectedMembers.length < 2) {
      ErrorDisplayService.showWarningSnackbar(
        context,
        l10n.t('group_form.members_requirement'),
      );
      return;
    }

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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEdit
              ? l10n.t('group_form.title_edit')
              : l10n.t('group_form.title_create'),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Text(
                l10n.t('group_form.avatar_title'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Center(child: _buildAvatarPicker(isEdit)),
              const SizedBox(height: 16),
              if (isEdit) ...[
                Text(
                  l10n.t('group_form.cover_title'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                _buildCoverPicker(),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: l10n.t('group_form.name_label'),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? l10n.t('group_form.name_required')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: InputDecoration(
                  labelText: l10n.t('group_form.description_label'),
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              _buildVisibilitySelector(),
              const SizedBox(height: 16),
              if (!isEdit) ...[
                _buildMemberSelection(),
                const SizedBox(height: 16),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: const Icon(Icons.save),
                  label: Text(
                    isEdit
                        ? l10n.t('plan_form.save_changes')
                        : l10n.t('group_form.title_create'),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatarPicker(bool isEdit) {
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
        backgroundColor: Colors.grey[200],
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
                          const Icon(Icons.group, size: 40, color: Colors.grey),
                      errorWidget: (context, url, error) =>
                          const Icon(Icons.group, size: 40, color: Colors.grey),
                    ),
                  );
                }
                return const Icon(Icons.group, size: 40, color: Colors.grey);
              })()
            : const Icon(Icons.group, size: 40, color: Colors.grey),
      ),
    );
  }

  Widget _buildCoverPicker() {
    final l10n = context.l10n;
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
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
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
                      const Icon(Icons.landscape, size: 40, color: Colors.grey),
                      const SizedBox(height: 8),
                      Text(
                        l10n.t('group_form.cover_loading'),
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                  errorWidget: (context, url, error) => Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.landscape, size: 40, color: Colors.grey),
                      const SizedBox(height: 8),
                      Text(
                        l10n.t('group_form.cover_pick'),
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.landscape, size: 40, color: Colors.grey),
                  const SizedBox(height: 8),
                  Text(
                    l10n.t('group_form.cover_pick'),
                    style: const TextStyle(color: Colors.grey),
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
                    ? Colors.red.shade100
                    : Colors.green.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedMembers.length < 2
                      ? Colors.red.shade300
                      : Colors.green.shade300,
                ),
              ),
              child: Text(
                '${_selectedMembers.length}/∞',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _selectedMembers.length < 2
                      ? Colors.red.shade700
                      : Colors.green.shade700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l10n.t('group_form.members_requirement'),
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 12),
        if (_loadingFriends)
          const Center(child: CircularProgressIndicator())
        else if (_availableFriends.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Center(child: Text(l10n.t('group_form.no_friends'))),
          )
        else
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
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
