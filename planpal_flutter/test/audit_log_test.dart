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
import 'test_app.dart';

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
        child: buildLocalizedTestApp(
          const Scaffold(
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
    expect(find.text('Updated plan: title'), findsOneWidget);
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

  testWidgets('AuditLogList keeps selected user stable after empty refresh', (
    tester,
  ) async {
    final repository = FakeAuditLogRepository(
      emptyWhenUserFilter: true,
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
          nextPageUrl: null,
          hasMore: false,
          pageSize: 20,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [auditLogRepositoryProvider.overrideWithValue(repository)],
        child: buildLocalizedTestApp(
          const Scaffold(
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

    await tester.tap(find.text('All users'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan Owner').last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Selected user'), findsOneWidget);
    expect(
      find.text('No audit activity matches the current filters.'),
      findsOneWidget,
    );
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
    final activityLog = buildLog(
      id: 'log-5',
      action: 'UPDATE_ACTIVITY',
      metadata: {
        'title': 'Dinner',
        'plan_id': 'internal-plan-id',
        'updated_fields': [
          'title',
          'description',
          'activity_type',
          'start_time',
          'end_time',
          'location_name',
          'location_address',
          'goong_place_id',
          'estimated_cost',
          'notes',
        ],
      },
    );
    final budgetLog = buildLog(
      id: 'log-6',
      action: 'UPDATE_BUDGET',
      metadata: {
        'plan_id': 'internal-plan-id',
        'plan_title': 'Da Nang Trip',
        'total_budget': '3000000.00',
        'currency': 'VND',
      },
    );
    final expenseLog = buildLog(
      id: 'log-7',
      action: 'CREATE_EXPENSE',
      metadata: {
        'expense_id': 'internal-expense-id',
        'plan_id': 'internal-plan-id',
        'plan_title': 'Da Nang Trip',
        'amount': '250000',
        'currency': 'VND',
        'category': 'food',
        'description': 'Dinner',
      },
    );

    expect(createPlanLog.metadataSummary, 'Created "Trip to Hoi An"');
    expect(roleLog.metadataSummary, 'Changed role to ADMIN');
    expect(
      activityLog.metadataSummary,
      'Updated activity "Dinner": title, description, activity type, start time, end time, location, address, estimated cost, and notes',
    );
    expect(activityLog.metadataSummary.contains('goong_place_id'), isFalse);
    expect(
      budgetLog.metadataSummary,
      'Updated budget for "Da Nang Trip" to 3000000 VND',
    );
    expect(budgetLog.metadataSummary.contains('plan_id'), isFalse);
    expect(
      expenseLog.metadataSummary,
      'Added expense to "Da Nang Trip": 250000 VND - food - "Dinner"',
    );
  });
}

class FakeAuditLogRepository extends AuditLogRepository {
  final List<AuditLogsResponse> globalPages;
  final List<AuditLogsResponse> resourcePages;
  final bool emptyWhenUserFilter;

  FakeAuditLogRepository({
    this.globalPages = const [],
    this.resourcePages = const [],
    this.emptyWhenUserFilter = false,
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
    if (emptyWhenUserFilter && filters.userId?.isNotEmpty == true) {
      return const AuditLogsResponse(
        logs: [],
        nextPageUrl: null,
        hasMore: false,
        pageSize: 20,
      );
    }
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
