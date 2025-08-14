import 'package:flutter/material.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:provider/provider.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';
import 'package:planpal_flutter/core/repositories/plan_repository.dart';
import 'package:intl/intl.dart';
import 'package:planpal_flutter/presentation/pages/users/plan_details_page.dart';
import 'package:planpal_flutter/presentation/pages/users/plan_form_page.dart';

class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  late final PlanRepository _repo;
  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _plans = const [];
  final DateFormat _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  @override
  void initState() {
    super.initState();
    _repo = PlanRepository(context.read<AuthProvider>());
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _repo.getPlans();
      if (!mounted) return;
      setState(() => _plans = data);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Lỗi: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'upcoming':
      case 'iscoming':
        return AppColors.info;
      case 'ongoing':
        return AppColors.warning;
      case 'completed':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      default:
        return Colors.grey;
    }
  }

  void _onCreatePlan() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const PlanFormPage()),
    );
    if (result != null &&
        result['action'] == 'created' &&
        result['plan'] != null) {
      final p = Map<String, dynamic>.from(result['plan'] as Map);
      if (!mounted) return;
      setState(() => _plans = [p, ..._plans]);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Tạo kế hoạch thành công')));
    }
  }

  void _onEditPlan(Map<String, dynamic> p) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => PlanFormPage(initial: p)),
    );
    if (result != null &&
        result['action'] == 'updated' &&
        result['plan'] != null) {
      final updated = Map<String, dynamic>.from(result['plan'] as Map);
      final id = updated['id'];
      if (!mounted) return;
      setState(
        () => _plans = _plans.map((e) => e['id'] == id ? updated : e).toList(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cập nhật kế hoạch thành công')),
      );
    }
  }

  void _onDeletePlan(Map<String, dynamic> p) async {
    final id = p['id'];
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xoá kế hoạch'),
        content: Text(
          "Bạn chắc chắn muốn xoá kế hoạch '${p['title'] ?? 'kế hoạch'}'?",
        ),
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
      await _repo.deletePlan(id);
      if (!mounted) return;
      setState(() => _plans = _plans.where((e) => e['id'] != id).toList());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã xoá kế hoạch')));
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
              'Kế hoạch',
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
                onPressed: _loadPlans,
              ),
            ],
          ),
        ],
        body: RefreshIndicator(onRefresh: _loadPlans, child: _buildBody()),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _onCreatePlan,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 8,
        icon: const Icon(Icons.add),
        label: const Text('Tạo kế hoạch'),
      ),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _buildError(_error!);
    if (_plans.isEmpty) return _buildEmpty();

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _plans.length,
      itemBuilder: (context, index) {
        final p = _plans[index];
        return _buildPlanCard(p, index, theme);
      },
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> p, int index, ThemeData theme) {
    final name = (p['title'] ?? 'Kế hoạch').toString();
    final dest = (p['description'] ?? '').toString();
    final status = (p['status'] ?? '').toString();
    final statusDisplay = (p['status_display'] ?? status).toString();
    final planType = (p['plan_type'] ?? 'personal').toString();
    final groupName = (p['group_name'] ?? p['group']?['name'] ?? '').toString();
    final start = p['start_date']?.toString();
    final end = p['end_date']?.toString();

    DateTime? startDt, endDt;
    try {
      if (start != null) startDt = DateTime.parse(start);
    } catch (_) {}
    try {
      if (end != null) endDt = DateTime.parse(end);
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Card(
        elevation: 2,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _handlePlanTap(p),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.getCardColor(index).withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.event_note,
                        color: AppColors.getCardColor(index),
                        size: 24,
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
                          if (dest.isNotEmpty)
                            Text(
                              dest,
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
                        if (v == 'edit') _onEditPlan(p);
                        if (v == 'delete') _onDeletePlan(p);
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'edit', child: Text('Sửa')),
                        PopupMenuItem(value: 'delete', child: Text('Xoá')),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Plan Type and Group Info
                if (planType == 'group' && groupName.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withAlpha(25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.group, size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          groupName,
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Date Information
                if (startDt != null || endDt != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        if (startDt != null)
                          Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Bắt đầu: ${_dateFmt.format(startDt)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        if (startDt != null && endDt != null)
                          const SizedBox(height: 4),
                        if (endDt != null)
                          Row(
                            children: [
                              Icon(
                                Icons.event_available,
                                size: 16,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Kết thúc: ${_dateFmt.format(endDt)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),

                const SizedBox(height: 12),

                // Bottom Row - Badges
                Row(
                  children: [
                    // Plan Type Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: planType == 'group'
                            ? AppColors.secondary.withAlpha(25)
                            : Colors.grey.withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: planType == 'group'
                              ? AppColors.secondary.withAlpha(75)
                              : Colors.grey.withAlpha(75),
                        ),
                      ),
                      child: Text(
                        planType == 'group' ? 'Nhóm' : 'Cá nhân',
                        style: TextStyle(
                          color: planType == 'group'
                              ? AppColors.secondary
                              : Colors.grey[700],
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Status Badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _statusColor(status).withAlpha(25),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _statusColor(status).withAlpha(75),
                        ),
                      ),
                      child: Text(
                        statusDisplay,
                        style: TextStyle(
                          color: _statusColor(status),
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ),

                    const Spacer(),

                    // Arrow Icon
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Colors.grey[400],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handlePlanTap(Map<String, dynamic> p) async {
    final id = p['id'];
    if (id != null) {
      final action = await Navigator.of(context).push<Map<String, dynamic>>(
        MaterialPageRoute(builder: (_) => PlanDetailsPage(id: id)),
      );
      if (action != null) {
        if (action['action'] == 'delete' && action['id'] == id) {
          _onDeletePlan(p);
        } else if (action['action'] == 'edit') {
          _onEditPlan(p);
        }
      }
    }
  }

  Widget _buildEmpty() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.event_busy, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Chưa có kế hoạch nào',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Tạo kế hoạch đầu tiên của bạn!',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ),
      ],
    );
  }

  Widget _buildError(String msg) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.error_outline, size: 64, color: Colors.redAccent[200]),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Có lỗi xảy ra',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            msg,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton.icon(
            onPressed: _loadPlans,
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}
