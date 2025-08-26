import 'package:flutter/material.dart';
import 'package:planpal_flutter/core/theme/app_colors.dart';
import 'package:provider/provider.dart';
import 'package:planpal_flutter/core/providers/auth_provider.dart';
import 'package:planpal_flutter/core/repositories/plan_repository.dart';
import 'package:intl/intl.dart';
import 'package:planpal_flutter/presentation/pages/users/plan_details_page.dart';
import 'package:planpal_flutter/presentation/pages/users/plan_form_page.dart';
import '../../../core/models/plan_summary.dart';
// Removed local PlanStatus mapping; use backend status + status_display

class PlanPage extends StatefulWidget {
  const PlanPage({super.key});

  @override
  State<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends State<PlanPage> {
  late final PlanRepository _repo;
  bool _loading = false;
  String? _error;
  List<PlanSummary> _plans = const [];
  final DateFormat _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  static const Map<String, Color> _statusColorMap = {
    'upcoming': AppColors.info,
    'ongoing': AppColors.warning,
    'completed': AppColors.success,
    'cancelled': AppColors.error,
  };

  Color _statusColor(String status) =>
      _statusColorMap[status.toLowerCase()] ?? Colors.grey;

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
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onCreatePlan() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const PlanFormPage()),
    );
    if (result != null &&
        result['action'] == 'created' &&
        result['plan'] is Map) {
      try {
        final summary = PlanSummary.fromJson(
          Map<String, dynamic>.from(result['plan'] as Map),
        );
        if (!mounted) return;
        setState(() => _plans = [summary, ..._plans]);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tạo kế hoạch thành công')),
        );
      } catch (_) {}
    }
  }

  void _onEditPlan(PlanSummary ps) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => PlanFormPage(initial: {'id': ps.id, 'title': ps.title}),
      ),
    );
    if (result != null &&
        result['action'] == 'updated' &&
        result['plan'] is Map) {
      try {
        final updatedSummary = PlanSummary.fromJson(
          Map<String, dynamic>.from(result['plan'] as Map),
        );
        if (!mounted) return;
        setState(
          () => _plans = _plans
              .map((p) => p.id == updatedSummary.id ? updatedSummary : p)
              .toList(),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cập nhật kế hoạch thành công')),
        );
      } catch (_) {}
    }
  }

  void _onDeletePlan(PlanSummary ps) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xoá kế hoạch'),
        content: Text("Bạn chắc chắn muốn xoá kế hoạch '${ps.title}'?"),
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
      await _repo.deletePlan(ps.id);
      if (!mounted) return;
      setState(() => _plans = _plans.where((p) => p.id != ps.id).toList());
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

  Future<void> _handlePlanTap(PlanSummary ps) async {
    final action = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => PlanDetailsPage(id: ps.id)),
    );
    if (action != null) {
      if (action['action'] == 'delete' && action['id'] == ps.id) {
        _onDeletePlan(ps);
      } else if (action['action'] == 'edit') {
        _onEditPlan(ps);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, inner) => [
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
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return _buildError(_error!);
    if (_plans.isEmpty) return _buildEmpty();
    final theme = Theme.of(context);
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _plans.length,
      itemBuilder: (context, index) =>
          _buildPlanCard(_plans[index], index, theme),
    );
  }

  Widget _buildPlanCard(PlanSummary p, int index, ThemeData theme) {
    final start = p.startDate;
    final end = p.endDate;
    String range = '';
    if (start != null) {
      range = _dateFmt.format(start);
      if (end != null) range += ' - ${_dateFmt.format(end)}';
    }
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
                            p.title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (range.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              range,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'edit') _onEditPlan(p);
                        if (v == 'delete') _onDeletePlan(p);
                      },
                      itemBuilder: (c) => const [
                        PopupMenuItem(value: 'edit', child: Text('Sửa')),
                        PopupMenuItem(value: 'delete', child: Text('Xoá')),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _badge(
                      p.planType == 'group' ? 'Nhóm' : 'Cá nhân',
                      p.planType == 'group' ? AppColors.secondary : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    _badge((p.statusDisplay), _statusColor(p.status)),
                    if (p.activitiesCount > 0) ...[
                      const SizedBox(width: 8),
                      _badge(
                        '${p.activitiesCount} hoạt động',
                        AppColors.primary,
                      ),
                    ],
                    const Spacer(),
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

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withAlpha(25),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withAlpha(75)),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontWeight: FontWeight.w500, fontSize: 12),
    ),
  );

  Widget _buildEmpty() => ListView(
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

  Widget _buildError(String msg) => ListView(
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
