import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/dtos/analytics_model.dart';
import 'package:planpal_flutter/core/dtos/user_model.dart';
import 'package:planpal_flutter/core/repositories/analytics_repository.dart';
import 'package:planpal_flutter/core/riverpod/analytics_providers.dart';
import 'package:planpal_flutter/core/riverpod/auth_notifier.dart';
import 'package:planpal_flutter/core/riverpod/repository_providers.dart';
import 'package:planpal_flutter/presentation/pages/analytics/analytics_dashboard_page.dart';

void main() {
  setUpAll(() async {
    dotenv.testLoad(fileInput: 'CLIENT_ID=test-client');
  });

  final summary = AnalyticsSummary(
    range: '30d',
    currentDate: DateTime(2026, 4, 5),
    generatedAt: DateTime(2026, 4, 6, 8),
    dau: const AnalyticsKpi(label: 'Daily Active Users', value: 18, changePct: 12.5),
    mau: const AnalyticsKpi(label: 'Monthly Active Users', value: 64, changePct: 8.4),
    planCreationRate: const AnalyticsKpi(
      label: 'Plan Creation Rate',
      value: 42.2,
      changePct: 20.0,
    ),
    planCompletionRate: const AnalyticsKpi(
      label: 'Plan Completion Rate',
      value: 41.7,
      changePct: 5.2,
    ),
    groupJoinRate: const AnalyticsKpi(
      label: 'Group Join Rate',
      value: 18.3,
      changePct: -2.0,
    ),
    notificationOpenRate: const AnalyticsKpi(
      label: 'Notification Open Rate',
      value: 52.4,
      changePct: 4.6,
    ),
    totals: const AnalyticsTotals(
      plansCreated: 27,
      plansCompleted: 11,
      groupJoins: 8,
      notificationsSent: 30,
      notificationsOpened: 16,
    ),
  );

  AnalyticsTimeSeries buildSeries(String metric, List<double> values) {
    return AnalyticsTimeSeries(
      metric: metric,
      range: '30d',
      points: [
        for (var index = 0; index < values.length; index += 1)
          TimeSeriesPoint(
            date: DateTime(2026, 4, index + 1),
            value: values[index],
          ),
      ],
    );
  }

  final topEntities = AnalyticsTopEntities(
    range: '30d',
    plans: const [
      TopAnalyticsEntity(
        id: 'plan-1',
        name: 'Da Nang Trip',
        resourceType: 'plan',
        metricLabel: 'events',
        value: 9,
      ),
    ],
    groups: const [
      TopAnalyticsEntity(
        id: 'group-1',
        name: 'Weekend Crew',
        resourceType: 'group',
        metricLabel: 'events',
        value: 7,
      ),
    ],
  );

  AuthProvider buildStaffAuthProvider() {
    final auth = AuthProvider();
    auth.setUser(
      UserModel(
        id: 'staff-user',
        username: 'staff',
        email: 'staff@example.com',
        firstName: 'Staff',
        lastName: 'Admin',
        phoneNumber: null,
        avatar: null,
        avatarUrl: null,
        hasAvatar: false,
        dateOfBirth: null,
        bio: null,
        isOnline: true,
        lastSeen: null,
        isRecentlyOnline: true,
        onlineStatus: 'online',
        plansCount: 0,
        personalPlansCount: 0,
        groupPlansCount: 0,
        groupsCount: 0,
        friendsCount: 0,
        unreadMessagesCount: 0,
        dateJoined: DateTime(2026, 1, 1),
        isActive: true,
        isStaff: true,
        fullName: 'Staff Admin',
        initials: 'SA',
      ),
    );
    return auth;
  }

  testWidgets('AnalyticsDashboardPage renders KPI cards and top entities', (
    tester,
  ) async {
    final repository = FakeAnalyticsRepository(
      summary: summary,
      seriesByMetric: {
        'dau': buildSeries('dau', [10, 12, 14, 16, 18]),
        'mau': buildSeries('mau', [30, 35, 40, 50, 64]),
        'plan_creation_rate': buildSeries('plan_creation_rate', [20, 28, 32, 39, 42]),
        'plan_completion_rate': buildSeries('plan_completion_rate', [15, 19, 23, 30, 41]),
        'group_join_rate': buildSeries('group_join_rate', [10, 11, 14, 16, 18]),
        'notification_open_rate': buildSeries(
          'notification_open_rate',
          [30, 35, 42, 48, 52],
        ),
      },
      topEntities: topEntities,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authNotifierProvider.overrideWithValue(buildStaffAuthProvider()),
          analyticsRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(home: AnalyticsDashboardPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Analytics Dashboard'), findsOneWidget);
    expect(find.text('Product Pulse'), findsOneWidget);
    expect(find.text('Daily Active Users'), findsWidgets);
    expect(find.text('18'), findsWidgets);

    await tester.scrollUntilVisible(
      find.text('Da Nang Trip'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Da Nang Trip'), findsOneWidget);
    expect(find.text('Weekend Crew'), findsOneWidget);
  });

  test('analytics providers load repository data', () async {
    final repository = FakeAnalyticsRepository(
      summary: summary,
      seriesByMetric: {
        'dau': buildSeries('dau', [10, 12, 14]),
        'mau': buildSeries('mau', [30, 40, 50]),
        'plan_creation_rate': buildSeries('plan_creation_rate', [22, 28, 33]),
        'plan_completion_rate': buildSeries('plan_completion_rate', [11, 18, 24]),
        'group_join_rate': buildSeries('group_join_rate', [12, 13, 15]),
        'notification_open_rate': buildSeries(
          'notification_open_rate',
          [20, 35, 50],
        ),
      },
      topEntities: topEntities,
    );

    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWithValue(buildStaffAuthProvider()),
        analyticsRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    final loadedSummary = await container.read(analyticsSummaryProvider.future);
    final timeSeries = await container.read(analyticsTimeSeriesProvider.future);
    final loadedTop = await container.read(analyticsTopEntitiesProvider.future);

    expect(loadedSummary.dau.value, 18);
    expect(timeSeries.metric, AnalyticsMetricKey.dau.apiValue);
    expect(timeSeries.points.length, 3);
    expect(loadedTop.plans.first.name, 'Da Nang Trip');
  });
}

class FakeAnalyticsRepository extends AnalyticsRepository {
  final AnalyticsSummary summary;
  final Map<String, AnalyticsTimeSeries> seriesByMetric;
  final AnalyticsTopEntities topEntities;

  FakeAnalyticsRepository({
    required this.summary,
    required this.seriesByMetric,
    required this.topEntities,
  }) : super(AuthProvider());

  @override
  Future<AnalyticsSummary> getDashboardSummary({String range = '30d'}) async {
    return summary;
  }

  @override
  Future<AnalyticsTimeSeries> getTimeSeries({
    required String metric,
    String range = '30d',
  }) async {
    return seriesByMetric[metric]!;
  }

  @override
  Future<AnalyticsTopEntities> getTopEntities({
    String range = '30d',
    int limit = 5,
  }) async {
    return topEntities;
  }
}
