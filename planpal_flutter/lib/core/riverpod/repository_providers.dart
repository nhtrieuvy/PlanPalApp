import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/audit_log_repository.dart';
import '../repositories/analytics_repository.dart';
import '../repositories/budget_repository.dart';
import '../repositories/plan_repository.dart';
import '../repositories/group_repository.dart';
import '../repositories/conversation_repository.dart';
import '../repositories/notification_repository.dart';
import '../repositories/user_repository.dart';
import '../repositories/friend_repository.dart';
import '../repositories/location_repository.dart';
import 'auth_notifier.dart';

/// All repository providers depend on [authNotifierProvider] so they
/// automatically get the current [AuthProvider] instance that already
/// contains token management and auto-refresh logic.
///
/// During the migration period the existing repository classes are kept
/// unchanged — they still receive an [AuthProvider].  Once the migration
/// is complete and repositories use a dedicated network provider,
/// these providers can be updated to inject that network client instead.

final planRepositoryProvider = Provider<PlanRepository>((ref) {
  final auth = ref.watch(authNotifierProvider);
  return PlanRepository(auth);
});

final auditLogRepositoryProvider = Provider<AuditLogRepository>((ref) {
  final auth = ref.watch(authNotifierProvider);
  return AuditLogRepository(auth);
});

final analyticsRepositoryProvider = Provider<AnalyticsRepository>((ref) {
  final auth = ref.watch(authNotifierProvider);
  return AnalyticsRepository(auth);
});

final budgetRepositoryProvider = Provider<BudgetRepository>((ref) {
  final auth = ref.watch(authNotifierProvider);
  return BudgetRepository(auth);
});

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  final auth = ref.watch(authNotifierProvider);
  return NotificationRepository(auth);
});

final groupRepositoryProvider = Provider<GroupRepository>((ref) {
  final auth = ref.watch(authNotifierProvider);
  return GroupRepository(auth);
});

final conversationRepositoryProvider = Provider<ConversationRepository>((ref) {
  final auth = ref.watch(authNotifierProvider);
  return ConversationRepository(auth);
});

final userRepositoryProvider = Provider<UserRepository>((ref) {
  final auth = ref.watch(authNotifierProvider);
  return UserRepository(auth);
});

final friendRepositoryProvider = Provider<FriendRepository>((ref) {
  final auth = ref.watch(authNotifierProvider);
  return FriendRepository(auth);
});

final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  final auth = ref.watch(authNotifierProvider);
  return LocationRepository(auth);
});
