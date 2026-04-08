import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/dtos/audit_log_model.dart';
import 'package:planpal_flutter/core/dtos/user_summary.dart';
import 'package:planpal_flutter/core/repositories/audit_log_repository.dart';
import 'package:planpal_flutter/core/riverpod/audit_logs_provider.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/presentation/widgets/audit/audit_log_list.dart';

void main() {
  setUpAll(() async {
    dotenv.testLoad(fileInput: 'CLIENT_ID=test-client');
  });

  final actor = UserSummary(
    id: 'user-1',
    username: 'owner',
    firstName: 'Plan',
    lastName: 'Owner',
    email: 'owner@example.com',
    isOnline: true,
    onlineStatus: 'online',
    avatarUrl: null,
    hasAvatar: false,
    dateJoined: DateTime(2025, 1, 1),
    lastSeen: DateTime(2025, 1, 1),
    fullName: 'Plan Owner',
    initials: 'PO',
  );

  AuditLogModel buildLog({
    required String id,
    required String action,
    required Map<String, dynamic> metadata,
  }) {
    return AuditLogModel(
      id: id,
      userId: actor.id,
      user: actor,
      action: action,
      resourceType: 'plan',
      resourceId: 'plan-1',
      metadata: metadata,
      createdAt: DateTime(2026, 1, 1, 9, 30),
    );
  }

  testWidgets('AuditLogList renders log content and filter controls', (
    tester,
  ) async {
    final repository = FakeAuditLogRepository(
      resourcePages: [
        AuditLogsResponse(
          logs: [
            buildLog(
              id: 'log-1',
              action: 'UPDATE_PLAN',
              metadata: {
                'updated_fields': ['title'],
              },
            ),
          ],
          nextPageUrl: 'page-2',
          hasMore: true,
          pageSize: 20,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [auditLogRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: Scaffold(
            body: AuditLogList(
              title: 'Plan Audit Log',
              resourceType: 'plan',
              resourceId: 'plan-1',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Plan Audit Log'), findsOneWidget);
    expect(find.text('Updated title'), findsOneWidget);
    expect(find.text('Plan Owner'), findsOneWidget);
    expect(find.text('All actions'), findsOneWidget);
    expect(find.text('All users'), findsOneWidget);
    expect(find.text('From date'), findsOneWidget);
    expect(find.text('To date'), findsOneWidget);
    expect(find.text('Load more'), findsOneWidget);
  });

  test('resourceAuditLogsProvider appends next page during loadMore', () async {
    final repository = FakeAuditLogRepository(
      resourcePages: [
        AuditLogsResponse(
          logs: [
            buildLog(
              id: 'log-1',
              action: 'UPDATE_PLAN',
              metadata: {
                'updated_fields': ['title'],
              },
            ),
          ],
          nextPageUrl: 'page-2',
          hasMore: true,
          pageSize: 20,
        ),
        AuditLogsResponse(
          logs: [
            buildLog(
              id: 'log-2',
              action: 'DELETE_PLAN',
              metadata: {'title': 'Trip to Da Nang'},
            ),
          ],
          nextPageUrl: null,
          hasMore: false,
          pageSize: 20,
        ),
      ],
    );

    final container = ProviderContainer(
      overrides: [auditLogRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    const query = AuditLogQuery(resourceType: 'plan', resourceId: 'plan-1');

    final initial = await container.read(
      resourceAuditLogsProvider(query).future,
    );
    expect(initial.items.length, 1);

    await container.read(resourceAuditLogsProvider(query).notifier).loadMore();
    final updated = container
        .read(resourceAuditLogsProvider(query))
        .valueOrNull;

    expect(updated, isNotNull);
    expect(updated!.items.length, 2);
    expect(updated.hasMore, isFalse);
    expect(updated.items.last.action, 'DELETE_PLAN');
  });

  test('audit log model builds readable metadata summaries', () {
    final createPlanLog = buildLog(
      id: 'log-3',
      action: 'CREATE_PLAN',
      metadata: {'title': 'Trip to Hoi An'},
    );
    final roleLog = buildLog(
      id: 'log-4',
      action: 'CHANGE_ROLE',
      metadata: {'new_role': 'admin'},
    );

    expect(createPlanLog.metadataSummary, 'Created "Trip to Hoi An"');
    expect(roleLog.metadataSummary, 'Changed role to ADMIN');
  });
}

class FakeAuditLogRepository extends AuditLogRepository {
  final List<AuditLogsResponse> globalPages;
  final List<AuditLogsResponse> resourcePages;

  FakeAuditLogRepository({
    this.globalPages = const [],
    this.resourcePages = const [],
  }) : super(AuthProvider());

  @override
  Future<AuditLogsResponse> getAuditLogs({
    AuditLogFilter filters = const AuditLogFilter(),
    String? nextPageUrl,
  }) async {
    return _selectPage(globalPages, nextPageUrl);
  }

  @override
  Future<AuditLogsResponse> getLogsByResource({
    required String resourceType,
    required String resourceId,
    AuditLogFilter filters = const AuditLogFilter(),
    String? nextPageUrl,
  }) async {
    return _selectPage(resourcePages, nextPageUrl);
  }

  Future<AuditLogsResponse> _selectPage(
    List<AuditLogsResponse> pages,
    String? nextPageUrl,
  ) async {
    if (pages.isEmpty) {
      return const AuditLogsResponse(
        logs: [],
        nextPageUrl: null,
        hasMore: false,
        pageSize: 20,
      );
    }

    if (nextPageUrl == null || pages.length == 1) {
      return pages.first;
    }
    return pages.last;
  }
}
