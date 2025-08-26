import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';
import 'package:planpal_flutter/core/repositories/group_repository.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../../core/models/group_detail.dart';

class GroupFormPage extends StatefulWidget {
  final Map<String, dynamic>? initial;
  const GroupFormPage({super.key, this.initial});

  @override
  State<GroupFormPage> createState() => _GroupFormPageState();
}

class _GroupFormPageState extends State<GroupFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  bool _submitting = false;
  File? _avatarFile;
  File? _coverFile;
  late final GroupRepository _repo;

  @override
  void initState() {
    super.initState();
    _repo = GroupRepository(context.read<AuthProvider>());
    _nameCtrl = TextEditingController(
      text: widget.initial?['name']?.toString() ?? '',
    );
    _descCtrl = TextEditingController(
      text: widget.initial?['description']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final payload = {
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
      };
      GroupDetail result;
      if (widget.initial == null) {
        // When creating a new group, only send avatar (no cover image)
        result = await _repo.createGroup(payload, avatar: _avatarFile);
        if (!mounted) return;

        // Evict any cached images for the returned URLs to avoid stale images
        try {
          final avatarUrl = result.avatarThumb ?? '';
          final coverUrl = result.coverImageUrl ?? '';
          if (avatarUrl.isNotEmpty) {
            CachedNetworkImage.evictFromCache(avatarUrl);
          }
          if (coverUrl.isNotEmpty) {
            CachedNetworkImage.evictFromCache(coverUrl);
          }
        } catch (_) {}

        Navigator.of(context).pop({'action': 'created', 'group': {
          'id': result.id,
          'name': result.name,
          'description': result.description,
          'avatar_thumb': result.avatarThumb,
          'cover_image_url': result.coverImageUrl,
          'members_count': result.memberCount,
        }});
      } else {
        final id = widget.initial!['id']; // id là String
        result = await _repo.updateGroup(
          id,
          payload,
          avatar: _avatarFile,
          coverImage: _coverFile,
        );
        if (!mounted) return;

        // Evict cache for changed image URLs so UI shows updates immediately
        try {
          final newAvatar = result.avatarThumb ?? '';
          final newCover = result.coverImageUrl ?? '';
          if (newAvatar.isNotEmpty) {
            CachedNetworkImage.evictFromCache(newAvatar);
          }
          if (newCover.isNotEmpty) {
            CachedNetworkImage.evictFromCache(newCover);
          }
        } catch (_) {}

        Navigator.of(context).pop({'action': 'updated', 'group': {
          'id': result.id,
          'name': result.name,
          'description': result.description,
          'avatar_thumb': result.avatarThumb,
          'cover_image_url': result.coverImageUrl,
          'members_count': result.memberCount,
        }});
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Sửa nhóm' : 'Tạo nhóm'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Avatar picker
              const Text(
                'Ảnh đại diện nhóm',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Center(
                child: GestureDetector(
                  onTap: () async {
                    final picker = ImagePicker();
                    final XFile? picked = await picker.pickImage(
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
                                  placeholder: (context, u) => const Icon(
                                    Icons.group,
                                    size: 40,
                                    color: Colors.grey,
                                  ),
                                  errorWidget: (context, u, error) =>
                                      const Icon(
                                        Icons.group,
                                        size: 40,
                                        color: Colors.grey,
                                      ),
                                ),
                              );
                            }
                            return const Icon(
                              Icons.group,
                              size: 40,
                              color: Colors.grey,
                            );
                          })()
                        : const Icon(Icons.group, size: 40, color: Colors.grey),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Cover image picker - only show when editing existing group
              if (isEdit) ...[
                const Text(
                  'Ảnh bìa nhóm (tùy chọn)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final picker = ImagePicker();
                    final XFile? picked = await picker.pickImage(
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
                              widget.initial!['cover_image_url']
                                  .toString()
                                  .isNotEmpty)
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: widget.initial!['cover_image_url'],
                              fit: BoxFit.cover,
                              placeholder: (context, url) => const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.landscape,
                                    size: 40,
                                    color: Colors.grey,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Đang tải ảnh bìa...',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                              errorWidget: (context, url, error) =>
                                  const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.landscape,
                                        size: 40,
                                        color: Colors.grey,
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        'Chọn ảnh bìa',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ],
                                  ),
                            ),
                          )
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.landscape,
                                size: 40,
                                color: Colors.grey,
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Chọn ảnh bìa',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tên nhóm',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Vui lòng nhập tên nhóm'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Mô tả',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: const Icon(Icons.save),
                  label: Text(isEdit ? 'Lưu thay đổi' : 'Tạo'),
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
}
