import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/dtos/notification_model.dart';
import 'package:planpal_flutter/core/repositories/notification_repository.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/riverpod/notifications_provider.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/presentation/pages/notifications/notification_list_page.dart';

void main() {
  setUpAll(() async {
    dotenv.testLoad(fileInput: 'CLIENT_ID=test-client');
  });

  NotificationModel buildNotification({
    required String id,
    required String type,
    required String title,
    required String message,
    bool isRead = false,
  }) {
    return NotificationModel(
      id: id,
      type: type,
      title: title,
      message: message,
      data: const {'group_name': 'PlanPal Group'},
      isRead: isRead,
      readAt: isRead ? DateTime(2026, 4, 5, 10, 30) : null,
      createdAt: DateTime(2026, 4, 5, 9, 30),
    );
  }

  testWidgets('NotificationListPage renders list and unread badge', (
    tester,
  ) async {
    final repository = FakeNotificationRepository(
      unreadCount: 3,
      pages: [
        NotificationsResponse(
          notifications: [
            buildNotification(
              id: 'notif-1',
              type: 'PLAN_UPDATED',
              title: 'Plan updated',
              message: 'Owner updated "Da Nang Trip".',
            ),
          ],
          nextPageUrl: null,
          hasMore: false,
          pageSize: 20,
          unreadCount: 3,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authNotifierProvider.overrideWithValue(AuthProvider()),
          notificationRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: NotificationListPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Plan updated'), findsWidgets);
    expect(find.text('Owner updated "Da Nang Trip".'), findsOneWidget);
    expect(find.text('Unread'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
  });

  test('notificationsProvider appends next page during loadMore', () async {
    final repository = FakeNotificationRepository(
      unreadCount: 1,
      pages: [
        NotificationsResponse(
          notifications: [
            buildNotification(
              id: 'notif-1',
              type: 'PLAN_UPDATED',
              title: 'Plan updated',
              message: 'Owner updated "Da Nang Trip".',
            ),
          ],
          nextPageUrl: 'page-2',
          hasMore: true,
          pageSize: 20,
          unreadCount: 1,
        ),
        NotificationsResponse(
          notifications: [
            buildNotification(
              id: 'notif-2',
              type: 'NEW_MESSAGE',
              title: 'New message',
              message: 'Alice: Hello',
            ),
          ],
          nextPageUrl: null,
          hasMore: false,
          pageSize: 20,
          unreadCount: 1,
        ),
      ],
    );

    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWithValue(AuthProvider()),
        notificationRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final initial = await container.read(notificationsProvider.future);
    expect(initial.items.length, 1);

    await container.read(notificationsProvider.notifier).loadMore();
    final updated = container.read(notificationsProvider).valueOrNull;

    expect(updated, isNotNull);
    expect(updated!.items.length, 2);
    expect(updated.hasMore, isFalse);
    expect(updated.items.last.type, 'NEW_MESSAGE');
  });

  test('unreadCountProvider reads unread count from repository', () async {
    final repository = FakeNotificationRepository(unreadCount: 5);
    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWithValue(AuthProvider()),
        notificationRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final unreadCount = await container.read(unreadCountProvider.future);
    expect(unreadCount, 5);
  });
}

class FakeNotificationRepository extends NotificationRepository {
  final List<NotificationsResponse> pages;
  final int unreadCount;
  final Set<String> markedReadIds = <String>{};
  bool markedAllAsRead = false;

  FakeNotificationRepository({this.pages = const [], this.unreadCount = 0})
    : super(AuthProvider());

  @override
  Future<NotificationsResponse> getNotifications({
    NotificationFilter filters = const NotificationFilter(),
    String? nextPageUrl,
  }) async {
    if (pages.isEmpty) {
      return NotificationsResponse(
        notifications: const [],
        nextPageUrl: null,
        hasMore: false,
        pageSize: filters.pageSize,
        unreadCount: unreadCount,
      );
    }

    if (nextPageUrl == null || pages.length == 1) {
      return pages.first;
    }
    return pages.last;
  }

  @override
  Future<int> getUnreadCount() async => unreadCount;

  @override
  Future<void> markAsRead(String notificationId) async {
    markedReadIds.add(notificationId);
  }

  @override
  Future<int> markAllAsRead() async {
    markedAllAsRead = true;
    return unreadCount;
  }
}
