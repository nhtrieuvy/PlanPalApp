import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/dtos/audit_log_model.dart';
import 'package:planpal_flutter/core/repositories/audit_log_repository.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';

class AuditLogFeedState {
  final List<AuditLogModel> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? nextPageUrl;
  final Object? loadMoreError;

  const AuditLogFeedState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.nextPageUrl,
    this.loadMoreError,
  });

  AuditLogFeedState copyWith({
    List<AuditLogModel>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? nextPageUrl,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return AuditLogFeedState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      nextPageUrl: nextPageUrl ?? this.nextPageUrl,
      loadMoreError: clearLoadMoreError
          ? null
          : (loadMoreError ?? this.loadMoreError),
    );
  }
}

class AuditLogsNotifier
    extends FamilyAsyncNotifier<AuditLogFeedState, AuditLogFilter> {
  late AuditLogRepository _repo;
  final Set<String> _loadedPageUrls = <String>{};
  bool _isRequestInFlight = false;

  @override
  Future<AuditLogFeedState> build(AuditLogFilter arg) async {
    _repo = ref.watch(auditLogRepositoryProvider);
    return _loadInitial(arg);
  }

  Future<AuditLogFeedState> _loadInitial(AuditLogFilter filters) async {
    if (_isRequestInFlight) {
      return state.valueOrNull ?? const AuditLogFeedState(isLoading: true);
    }

    _isRequestInFlight = true;
    try {
      final response = await _repo.getAuditLogs(filters: filters);
      _loadedPageUrls
        ..clear()
        ..add('FIRST_PAGE');
      return AuditLogFeedState(
        items: response.logs,
        hasMore: response.hasMore,
        nextPageUrl: response.nextPageUrl,
      );
    } finally {
      _isRequestInFlight = false;
    }
  }

  Future<void> refresh() async {
    state = AsyncData(
      (state.valueOrNull ?? const AuditLogFeedState()).copyWith(
        isLoading: true,
        clearLoadMoreError: true,
      ),
    );
    state = await AsyncValue.guard(() => _loadInitial(arg));
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || _isRequestInFlight) return;
    if (current.isLoading || current.isLoadingMore) return;
    if (current.nextPageUrl == null) return;
    if (_loadedPageUrls.contains(current.nextPageUrl)) return;

    state = AsyncData(
      current.copyWith(isLoadingMore: true, clearLoadMoreError: true),
    );

    _isRequestInFlight = true;
    try {
      final response = await _repo.getAuditLogs(
        filters: arg,
        nextPageUrl: current.nextPageUrl,
      );
      final existingIds = current.items.map((item) => item.id).toSet();
      final appended = response.logs
          .where((item) => !existingIds.contains(item.id))
          .toList();
      _loadedPageUrls.add(current.nextPageUrl!);
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...appended],
          isLoadingMore: false,
          hasMore: response.hasMore,
          nextPageUrl: response.nextPageUrl,
          clearLoadMoreError: true,
        ),
      );
    } catch (error) {
      state = AsyncData(
        current.copyWith(isLoadingMore: false, loadMoreError: error),
      );
    } finally {
      _isRequestInFlight = false;
    }
  }
}

class ResourceAuditLogsNotifier
    extends FamilyAsyncNotifier<AuditLogFeedState, AuditLogQuery> {
  late AuditLogRepository _repo;
  final Set<String> _loadedPageUrls = <String>{};
  bool _isRequestInFlight = false;

  @override
  Future<AuditLogFeedState> build(AuditLogQuery arg) async {
    _repo = ref.watch(auditLogRepositoryProvider);
    return _loadInitial(arg);
  }

  Future<AuditLogFeedState> _loadInitial(AuditLogQuery query) async {
    if (_isRequestInFlight) {
      return state.valueOrNull ?? const AuditLogFeedState(isLoading: true);
    }

    _isRequestInFlight = true;
    try {
      final response = await _repo.getLogsByResource(
        resourceType: query.resourceType,
        resourceId: query.resourceId,
        filters: query.filters,
      );
      _loadedPageUrls
        ..clear()
        ..add('FIRST_PAGE');
      return AuditLogFeedState(
        items: response.logs,
        hasMore: response.hasMore,
        nextPageUrl: response.nextPageUrl,
      );
    } finally {
      _isRequestInFlight = false;
    }
  }

  Future<void> refresh() async {
    state = AsyncData(
      (state.valueOrNull ?? const AuditLogFeedState()).copyWith(
        isLoading: true,
        clearLoadMoreError: true,
      ),
    );
    state = await AsyncValue.guard(() => _loadInitial(arg));
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || _isRequestInFlight) return;
    if (current.isLoading || current.isLoadingMore) return;
    if (current.nextPageUrl == null) return;
    if (_loadedPageUrls.contains(current.nextPageUrl)) return;

    state = AsyncData(
      current.copyWith(isLoadingMore: true, clearLoadMoreError: true),
    );

    _isRequestInFlight = true;
    try {
      final response = await _repo.getLogsByResource(
        resourceType: arg.resourceType,
        resourceId: arg.resourceId,
        filters: arg.filters,
        nextPageUrl: current.nextPageUrl,
      );
      final existingIds = current.items.map((item) => item.id).toSet();
      final appended = response.logs
          .where((item) => !existingIds.contains(item.id))
          .toList();
      _loadedPageUrls.add(current.nextPageUrl!);
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...appended],
          isLoadingMore: false,
          hasMore: response.hasMore,
          nextPageUrl: response.nextPageUrl,
          clearLoadMoreError: true,
        ),
      );
    } catch (error) {
      state = AsyncData(
        current.copyWith(isLoadingMore: false, loadMoreError: error),
      );
    } finally {
      _isRequestInFlight = false;
    }
  }
}

final auditLogsProvider =
    AsyncNotifierProvider.family<
      AuditLogsNotifier,
      AuditLogFeedState,
      AuditLogFilter
    >(AuditLogsNotifier.new);

final resourceAuditLogsProvider =
    AsyncNotifierProvider.family<
      ResourceAuditLogsNotifier,
      AuditLogFeedState,
      AuditLogQuery
    >(ResourceAuditLogsNotifier.new);
