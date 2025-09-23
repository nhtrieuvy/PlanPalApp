import 'package:flutter/material.dart';
import '../repositories/plan_repository.dart';
import '../dtos/plan_summary.dart';

class PlanProvider extends ChangeNotifier {
  final PlanRepository _repository;

  PlanProvider(this._repository);

  List<PlanSummary> _plans = [];
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;
  String? _nextCursor;

  // Getters
  List<PlanSummary> get plans => List.unmodifiable(_plans);
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;
  String? get error => _error;

  /// Load plans with pagination support
  Future<void> loadPlans({bool refresh = false}) async {
    if (_isLoading) return;
    if (!refresh && !_hasMore) return;

    _setLoading(true);
    _setError(null);

    try {
      final cursor = refresh ? null : _nextCursor;
      final response = await _repository.getPlans(cursor: cursor);

      if (refresh) {
        _plans = response.plans;
      } else {
        _plans = [..._plans, ...response.plans];
      }

      _nextCursor = response.nextCursor;
      _hasMore = response.hasMore;

      notifyListeners();
    } catch (e) {
      _setError(e.toString());
    } finally {
      _setLoading(false);
    }
  }

  /// Filter plans by type
  List<PlanSummary> getPlansByType(String? type) {
    if (type == null || type == 'all') return _plans;
    return _plans.where((plan) => plan.planType == type).toList();
  }

  /// Add a new plan to the beginning of the list
  void addPlan(PlanSummary plan) {
    _plans = [plan, ..._plans];
    notifyListeners();
  }

  /// Update an existing plan
  void updatePlan(PlanSummary updatedPlan) {
    final index = _plans.indexWhere((p) => p.id == updatedPlan.id);
    if (index >= 0) {
      _plans[index] = updatedPlan;
      notifyListeners();
    }
  }

  /// Remove a plan
  void removePlan(String planId) {
    _plans = _plans.where((p) => p.id != planId).toList();
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _setError(null);
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }
}
