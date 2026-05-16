import 'package:planpal_flutter/core/dtos/group_summary.dart';
import 'package:planpal_flutter/core/dtos/user_summary.dart';
import 'package:planpal_flutter/core/utils/server_datetime.dart';

class GroupInviteModel {
  final String id;
  final String groupId;
  final String token;
  final String inviteCode;
  final String groupVisibility;
  final UserSummary? createdBy;
  final DateTime? expiresAt;
  final int? maxUses;
  final int currentUses;
  final int? remainingUses;
  final bool isActive;
  final bool isExpired;
  final String deepLink;
  final String webLink;
  final DateTime createdAt;
  final DateTime? updatedAt;

  const GroupInviteModel({
    required this.id,
    required this.groupId,
    required this.token,
    required this.inviteCode,
    required this.groupVisibility,
    required this.createdBy,
    required this.expiresAt,
    required this.maxUses,
    required this.currentUses,
    required this.remainingUses,
    required this.isActive,
    required this.isExpired,
    required this.deepLink,
    required this.webLink,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isUsable {
    if (!isActive || isExpired) return false;
    if (maxUses != null && remainingUses != null && remainingUses! <= 0) {
      return false;
    }
    return true;
  }

  factory GroupInviteModel.fromJson(Map<String, dynamic> json) {
    final createdByRaw = json['created_by'];
    return GroupInviteModel(
      id: json['id']?.toString() ?? '',
      groupId: json['group']?.toString() ?? json['group_id']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      inviteCode:
          json['invite_code']?.toString() ?? json['token']?.toString() ?? '',
      groupVisibility: json['group_visibility']?.toString() ?? 'private',
      createdBy: createdByRaw is Map
          ? UserSummary.fromJson(Map<String, dynamic>.from(createdByRaw))
          : null,
      expiresAt: parseServerDateTime(json['expires_at']),
      maxUses: _parseInt(json['max_uses']),
      currentUses: _parseInt(json['current_uses']) ?? 0,
      remainingUses: _parseInt(json['remaining_uses']),
      isActive: json['is_active'] == true,
      isExpired: json['is_expired'] == true,
      deepLink: json['deep_link']?.toString() ?? '',
      webLink: json['web_link']?.toString() ?? '',
      createdAt: parseServerDateTime(json['created_at']) ?? DateTime.now(),
      updatedAt: parseServerDateTime(json['updated_at']),
    );
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }
}

class CreateGroupInviteRequest {
  final DateTime? expiresAt;
  final int? maxUses;

  const CreateGroupInviteRequest({this.expiresAt, this.maxUses});

  Map<String, dynamic> toJson() => {
    if (expiresAt != null) 'expires_at': expiresAt!.toUtc().toIso8601String(),
    if (maxUses != null) 'max_uses': maxUses,
  };
}

class JoinGroupInviteResult {
  final String message;
  final String status;
  final GroupSummary group;
  final String? membershipRole;
  final GroupJoinRequestModel? joinRequest;

  const JoinGroupInviteResult({
    required this.message,
    required this.status,
    required this.group,
    required this.membershipRole,
    required this.joinRequest,
  });

  factory JoinGroupInviteResult.fromJson(Map<String, dynamic> json) {
    final groupRaw = json['group_summary'];
    final groupMap = groupRaw is Map
        ? Map<String, dynamic>.from(groupRaw)
        : <String, dynamic>{};
    final requestRaw = json['join_request'];
    return JoinGroupInviteResult(
      message: json['message']?.toString() ?? '',
      status: json['status']?.toString() ?? 'joined',
      group: GroupSummary.fromJson(groupMap),
      membershipRole: json['membership_role']?.toString(),
      joinRequest: requestRaw is Map
          ? GroupJoinRequestModel.fromJson(
              Map<String, dynamic>.from(requestRaw),
            )
          : null,
    );
  }
}

class GroupJoinRequestModel {
  final String id;
  final String groupId;
  final String? inviteId;
  final String? inviteToken;
  final UserSummary user;
  final String status;
  final UserSummary? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime createdAt;

  const GroupJoinRequestModel({
    required this.id,
    required this.groupId,
    required this.inviteId,
    required this.inviteToken,
    required this.user,
    required this.status,
    required this.reviewedBy,
    required this.reviewedAt,
    required this.createdAt,
  });

  factory GroupJoinRequestModel.fromJson(Map<String, dynamic> json) {
    final userRaw = json['user'];
    final reviewedByRaw = json['reviewed_by'];
    return GroupJoinRequestModel(
      id: json['id']?.toString() ?? '',
      groupId: json['group']?.toString() ?? '',
      inviteId: json['invite']?.toString(),
      inviteToken: json['invite_token']?.toString(),
      user: userRaw is Map
          ? UserSummary.fromJson(Map<String, dynamic>.from(userRaw))
          : UserSummary.fromJson(const <String, dynamic>{}),
      status: json['status']?.toString() ?? 'pending',
      reviewedBy: reviewedByRaw is Map
          ? UserSummary.fromJson(Map<String, dynamic>.from(reviewedByRaw))
          : null,
      reviewedAt: parseServerDateTime(json['reviewed_at']),
      createdAt: parseServerDateTime(json['created_at']) ?? DateTime.now(),
    );
  }
}
