class CreateGroupRequest {
  final String name;
  final String description;
  final String visibility;
  final List<String> initialMembers;

  CreateGroupRequest({
    required this.name,
    required this.description,
    this.visibility = 'private',
    required this.initialMembers,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'visibility': visibility,
    'initial_members': initialMembers,
  };
}

class UpdateGroupRequest {
  final String? name;
  final String? description;
  final String? visibility;

  UpdateGroupRequest({this.name, this.description, this.visibility});

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    if (name != null) data['name'] = name;
    if (description != null) data['description'] = description;
    if (visibility != null) data['visibility'] = visibility;
    return data;
  }
}

class JoinGroupRequest {
  final String groupId;

  JoinGroupRequest({required this.groupId});

  Map<String, dynamic> toJson() => {'group_id': groupId};
}

class AddMemberRequest {
  final String userId;

  AddMemberRequest({required this.userId});

  Map<String, dynamic> toJson() => {'user_id': userId};
}

class RemoveMemberRequest {
  final String userId;

  RemoveMemberRequest({required this.userId});

  Map<String, dynamic> toJson() => {'user_id': userId};
}

class ChangeMemberRoleRequest {
  final String userId;
  final String role;

  ChangeMemberRoleRequest({required this.userId, required this.role});

  Map<String, dynamic> toJson() => {'user_id': userId, 'role': role};
}
