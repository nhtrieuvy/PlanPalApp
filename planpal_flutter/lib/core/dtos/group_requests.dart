class CreateGroupRequest {
  final String name;
  final String description;
  final List<String> initialMembers;

  CreateGroupRequest({
    required this.name,
    required this.description,
    required this.initialMembers,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'initial_members': initialMembers,
  };
}

class UpdateGroupRequest {
  final String? name;
  final String? description;

  UpdateGroupRequest({this.name, this.description});

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    if (name != null) data['name'] = name;
    if (description != null) data['description'] = description;
    return data;
  }
}

class JoinGroupRequest {
  final String? groupId;
  final String? inviteCode;

  JoinGroupRequest({this.groupId, this.inviteCode});

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};
    if (groupId != null) data['group_id'] = groupId;
    if (inviteCode != null) data['invite_code'] = inviteCode;
    return data;
  }
}

class AddMemberRequest {
  final String userId;

  AddMemberRequest({required this.userId});

  Map<String, dynamic> toJson() => {'user_id': userId};
}
