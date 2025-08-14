import 'package:flutter/material.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:provider/provider.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';
import 'package:planpal_flutter/core/repositories/group_repository.dart';
import 'package:planpal_flutter/presentation/pages/users/group_details_page.dart';
import 'package:planpal_flutter/presentation/pages/users/group_form_page.dart';

class GroupPage extends StatefulWidget {
  const GroupPage({super.key});

  @override
  State<GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<GroupPage> {
  late final GroupRepository _repo;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _groups = const [];

  @override
  void initState() {
    super.initState();
    _repo = GroupRepository(context.read<AuthProvider>());
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _repo.getGroups();
      if (!mounted) return;
      setState(() => _groups = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Lỗi: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _initialsFrom(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts
        .take(2)
        .map((e) => e.isNotEmpty ? e[0] : '')
        .join()
        .toUpperCase();
  }

  void _onCreateGroup() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const GroupFormPage()),
    );
    if (result != null &&
        result['action'] == 'created' &&
        result['group'] != null) {
      final g = Map<String, dynamic>.from(result['group'] as Map);
      if (!mounted) return;
      setState(() => _groups = [g, ..._groups]);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Tạo nhóm thành công')));
    }
  }

  void _onEditGroup(Map<String, dynamic> g) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => GroupFormPage(initial: g)),
    );
    if (result != null &&
        result['action'] == 'updated' &&
        result['group'] != null) {
      final updated = Map<String, dynamic>.from(result['group'] as Map);
      final id = updated['id']; // id là String
      if (!mounted) return;
      setState(
        () =>
            _groups = _groups.map((e) => e['id'] == id ? updated : e).toList(),
      );
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Cập nhật nhóm thành công')));
    }
  }

  void _onDeleteGroup(Map<String, dynamic> g) async {
    final id = g['id']; // id là String
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xoá nhóm'),
        content: Text("Bạn chắc chắn muốn xoá nhóm '${g['name']}'?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _repo.deleteGroup(id);
      if (!mounted) return;
      setState(() => _groups = _groups.where((e) => e['id'] != id).toList());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã xoá nhóm')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            title: const Text(
              'Nhóm',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            centerTitle: true,
            floating: true,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadGroups,
              ),
            ],
          ),
        ],
        body: RefreshIndicator(onRefresh: _loadGroups, child: _buildBody()),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _onCreateGroup,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 8,
        icon: const Icon(Icons.group_add),
        label: const Text('Tạo nhóm'),
      ),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _buildError(_error!);
    }
    if (_groups.isEmpty) {
      return _buildEmpty();
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _groups.length,
      itemBuilder: (context, index) {
        final g = _groups[index];
        return _buildGroupCard(g, index, theme);
      },
    );
  }

  Widget _buildGroupCard(Map<String, dynamic> g, int index, ThemeData theme) {
    final name = (g['name'] ?? 'Nhóm không tên').toString();
    final desc = (g['description'] ?? '').toString();
    final membersCount =
        g['members_count'] ??
        g['member_count'] ??
        (g['members'] is List ? (g['members'] as List).length : 0);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 2,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _handleGroupTap(g),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: AppColors.getCardColor(index).withAlpha(25),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Text(
                          _initialsFrom(name),
                          style: TextStyle(
                            color: AppColors.getCardColor(index),
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          if (desc.isNotEmpty)
                            Text(
                              desc,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: Colors.grey[600],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'edit') _onEditGroup(g);
                        if (v == 'delete') _onDeleteGroup(g);
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'edit', child: Text('Sửa')),
                        PopupMenuItem(value: 'delete', child: Text('Xoá')),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Members Info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.people_alt_outlined,
                        size: 20,
                        color: AppColors.secondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$membersCount thành viên',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.grey[400],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleGroupTap(Map<String, dynamic> g) async {
    final id = g['id'];
    if (id != null) {
      final action = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(builder: (_) => GroupDetailsPage(id: id)),
      );
      if (action != null) {
        if (action['action'] == 'delete' && action['id'] == id) {
          _onDeleteGroup(g);
        } else if (action['action'] == 'edit') {
          _onEditGroup(g);
        }
      }
    }
  }

  Widget _buildEmpty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 120),
        Icon(Icons.group_outlined, size: 64, color: Colors.grey),
        SizedBox(height: 12),
        Center(child: Text('Chưa có nhóm nào', style: TextStyle(fontSize: 16))),
      ],
    );
  }

  Widget _buildError(String msg) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.error_outline, size: 64, color: Colors.redAccent),
        const SizedBox(height: 12),
        Center(child: Text(msg, textAlign: TextAlign.center)),
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton.icon(
            onPressed: _loadGroups,
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
          ),
        ),
      ],
    );
  }
}
