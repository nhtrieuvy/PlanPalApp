import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/dtos/notification_model.dart';
import 'package:planpal_flutter/core/repositories/notification_repository.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/core/services/notification_websocket_service.dart';

class NotificationFeedState {
  final List<NotificationModel> items;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final String? nextPageUrl;
  final int unreadCount;
  final Object? loadMoreError;

  const NotificationFeedState({
    this.items = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.nextPageUrl,
    this.unreadCount = 0,
    this.loadMoreError,
  });

  NotificationFeedState copyWith({
    List<NotificationModel>? items,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    String? nextPageUrl,
    int? unreadCount,
    Object? loadMoreError,
    bool clearLoadMoreError = false,
  }) {
    return NotificationFeedState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      nextPageUrl: nextPageUrl ?? this.nextPageUrl,
      unreadCount: unreadCount ?? this.unreadCount,
      loadMoreError: clearLoadMoreError
          ? null
          : (loadMoreError ?? this.loadMoreError),
    );
  }
}

class NotificationsNotifier
    extends AutoDisposeAsyncNotifier<NotificationFeedState> {
  late NotificationRepository _repo;
  late NotificationWebSocketService _service;
  late AuthProvider _auth;
  final Set<String> _loadedPageUrls = <String>{};
  NotificationFilter _currentFilter = const NotificationFilter();
  StreamSubscription<NotificationSocketEvent>? _subscription;
  bool _isRequestInFlight = false;
  bool _realtimeConfigured = false;

  @override
  Future<NotificationFeedState> build() async {
    _repo = ref.watch(notificationRepositoryProvider);
    _service = ref.watch(notificationWebSocketServiceProvider);
    _auth = ref.watch(authNotifierProvider);
    _configureRealtime();
    return _loadInitial();
  }

  NotificationFilter get currentFilter => _currentFilter;

  Future<NotificationFeedState> _loadInitial() async {
    if (_isRequestInFlight) {
      return state.valueOrNull ?? const NotificationFeedState(isLoading: true);
    }

    _isRequestInFlight = true;
    try {
      final response = await _repo.getNotifications(filters: _currentFilter);
      _loadedPageUrls
        ..clear()
        ..add('FIRST_PAGE');
      return NotificationFeedState(
        items: response.notifications,
        hasMore: response.hasMore,
        nextPageUrl: response.nextPageUrl,
        unreadCount: response.unreadCount,
      );
    } finally {
      _isRequestInFlight = false;
    }
  }

  Future<void> refresh() async {
    state = AsyncData(
      (state.valueOrNull ?? const NotificationFeedState()).copyWith(
        isLoading: true,
        clearLoadMoreError: true,
      ),
    );
    state = await AsyncValue.guard(_loadInitial);
  }

  Future<void> updateFilter(NotificationFilter filter) async {
    _currentFilter = filter;
    await refresh();
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
      final response = await _repo.getNotifications(
        filters: _currentFilter,
        nextPageUrl: current.nextPageUrl,
      );
      final existingIds = current.items.map((item) => item.id).toSet();
      final appended = response.notifications
          .where((item) => !existingIds.contains(item.id))
          .toList();
      _loadedPageUrls.add(current.nextPageUrl!);
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...appended],
          isLoadingMore: false,
          hasMore: response.hasMore,
          nextPageUrl: response.nextPageUrl,
          unreadCount: response.unreadCount,
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

  Future<void> markAsRead(String notificationId) async {
    final current = state.valueOrNull;
    if (current == null) return;

    final target = current.items.where((item) => item.id == notificationId);
    if (target.isEmpty || target.first.isRead) return;

    final previous = current;
    final updatedItems = _applySingleRead(previous.items, notificationId);
    state = AsyncData(
      previous.copyWith(
        items: _currentFilter.isRead == false
            ? updatedItems.where((item) => item.id != notificationId).toList()
            : updatedItems,
        unreadCount: _nextUnreadCount(previous.unreadCount, -1),
      ),
    );

    try {
      await _repo.markAsRead(notificationId);
    } catch (error) {
      state = AsyncData(previous);
      rethrow;
    }
  }

  Future<void> markAllAsRead() async {
    final current = state.valueOrNull;
    if (current == null || current.unreadCount == 0) return;

    final previous = current;
    state = AsyncData(
      previous.copyWith(
        items: _currentFilter.isRead == false
            ? const []
            : previous.items
                  .map(
                    (item) => item.isRead
                        ? item
                        : item.copyWith(isRead: true, readAt: DateTime.now()),
                  )
                  .toList(),
        unreadCount: 0,
      ),
    );

    try {
      await _repo.markAllAsRead();
    } catch (error) {
      state = AsyncData(previous);
      rethrow;
    }
  }

  void _configureRealtime() {
    if (_realtimeConfigured) return;
    _realtimeConfigured = true;

    _ensureRealtimeConnection();

    _subscription = _service.eventStream.listen(_handleRealtimeEvent);
    ref.onDispose(() {
      unawaited(_subscription?.cancel() ?? Future<void>.value());
    });
  }

  void _handleRealtimeEvent(NotificationSocketEvent event) {
    final current = state.valueOrNull;
    if (current == null) return;

    switch (event.type) {
      case NotificationSocketEventType.created:
        final notification = event.notification;
        if (notification == null) return;
        final alreadyExists = current.items.any(
          (item) => item.id == notification.id,
        );
        final shouldInclude = _matchesCurrentFilter(notification);
        state = AsyncData(
          current.copyWith(
            items: shouldInclude && !alreadyExists
                ? [notification, ...current.items]
                : current.items,
            unreadCount: event.unreadCount ?? current.unreadCount,
          ),
        );
        break;
      case NotificationSocketEventType.read:
        final notificationId = event.notificationId;
        if (notificationId == null) return;
        final updated = _applySingleRead(current.items, notificationId);
        state = AsyncData(
          current.copyWith(
            items: _currentFilter.isRead == false
                ? updated.where((item) => item.id != notificationId).toList()
                : updated,
            unreadCount: event.unreadCount ?? current.unreadCount,
          ),
        );
        break;
      case NotificationSocketEventType.readAll:
        state = AsyncData(
          current.copyWith(
            items: _currentFilter.isRead == false
                ? const []
                : current.items
                      .map(
                        (item) => item.isRead
                            ? item
                            : item.copyWith(
                                isRead: true,
                                readAt: DateTime.now(),
                              ),
                      )
                      .toList(),
            unreadCount: event.unreadCount ?? 0,
          ),
        );
        break;
      case NotificationSocketEventType.unknown:
        break;
    }
  }

  List<NotificationModel> _applySingleRead(
    List<NotificationModel> items,
    String notificationId,
  ) {
    return [
      for (final item in items)
        if (item.id == notificationId)
          item.copyWith(isRead: true, readAt: DateTime.now())
        else
          item,
    ];
  }

  bool _matchesCurrentFilter(NotificationModel notification) {
    if (_currentFilter.isRead == null) return true;
    return notification.isRead == _currentFilter.isRead;
  }

  int _nextUnreadCount(int current, int delta) {
    final next = current + delta;
    return next < 0 ? 0 : next;
  }

  void _ensureRealtimeConnection() {
    final token = _auth.token;
    if (token != null && token.isNotEmpty) {
      unawaited(_service.connect(token));
    }
  }
}

class UnreadCountNotifier extends AutoDisposeAsyncNotifier<int> {
  static const Duration _pollingInterval = Duration(seconds: 60);

  late NotificationRepository _repo;
  late NotificationWebSocketService _service;
  late AuthProvider _auth;
  StreamSubscription<NotificationSocketEvent>? _subscription;
  Timer? _pollingTimer;
  bool _realtimeConfigured = false;

  @override
  Future<int> build() async {
    _repo = ref.watch(notificationRepositoryProvider);
    _service = ref.watch(notificationWebSocketServiceProvider);
    _auth = ref.watch(authNotifierProvider);
    _configureRealtime();
    _startPolling();
    return _repo.getUnreadCount();
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent) state = const AsyncLoading();
    state = await AsyncValue.guard(_repo.getUnreadCount);
  }

  void _configureRealtime() {
    if (_realtimeConfigured) return;
    _realtimeConfigured = true;

    _ensureRealtimeConnection();

    _subscription = _service.eventStream.listen((event) {
      final current = state.valueOrNull ?? 0;
      switch (event.type) {
        case NotificationSocketEventType.created:
          state = AsyncData(event.unreadCount ?? current + 1);
          break;
        case NotificationSocketEventType.read:
          state = AsyncData(
            event.unreadCount ?? (current > 0 ? current - 1 : 0),
          );
          break;
        case NotificationSocketEventType.readAll:
          state = AsyncData(event.unreadCount ?? 0);
          break;
        case NotificationSocketEventType.unknown:
          break;
      }
    });

    ref.onDispose(() {
      _pollingTimer?.cancel();
      unawaited(_subscription?.cancel() ?? Future<void>.value());
    });
  }

  void _startPolling() {
    _pollingTimer ??= Timer.periodic(_pollingInterval, (_) {
      if (!_service.isConnected) {
        _ensureRealtimeConnection();
        unawaited(refresh(silent: true));
      }
    });
  }

  void _ensureRealtimeConnection() {
    final token = _auth.token;
    if (token != null && token.isNotEmpty) {
      unawaited(_service.connect(token));
    }
  }
}

final notificationWebSocketServiceProvider =
    Provider.autoDispose<NotificationWebSocketService>((ref) {
      final service = NotificationWebSocketService();
      ref.onDispose(service.dispose);
      return service;
    });

final notificationsProvider =
    AsyncNotifierProvider.autoDispose<
      NotificationsNotifier,
      NotificationFeedState
    >(NotificationsNotifier.new);

final unreadCountProvider =
    AsyncNotifierProvider.autoDispose<UnreadCountNotifier, int>(
      UnreadCountNotifier.new,
    );
