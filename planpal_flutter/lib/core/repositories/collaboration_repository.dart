import 'package:dio/dio.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/dtos/collaboration_models.dart';
import 'package:planpal_flutter/core/dtos/plan_model.dart';
import 'package:planpal_flutter/core/services/api_error.dart';
import 'package:planpal_flutter/core/services/apis.dart';

class CollaborationRepository {
  final AuthProvider _auth;

  CollaborationRepository(this._auth);

  Future<List<AvailabilityPollModel>> getPolls(String groupId) async {
    final response = await _request(
      (client) => client.dio.get(Endpoints.groupAvailabilityPolls(groupId)),
    );
    return _list(response.data).map(AvailabilityPollModel.fromJson).toList();
  }

  Future<void> createPoll(String groupId, Map<String, dynamic> data) async {
    await _request(
      (client) => client.dio.post(
        Endpoints.groupAvailabilityPolls(groupId),
        data: data,
      ),
    );
  }

  Future<void> vote(String pollId, String optionId, String voteStatus) async {
    await _request(
      (client) => client.dio.post(
        Endpoints.availabilityPollVote(pollId),
        data: {'option_id': optionId, 'status': voteStatus},
      ),
    );
  }

  Future<List<PlanWorkItemModel>> getWorkItems(String planId) async {
    final response = await _request(
      (client) => client.dio.get(Endpoints.planWorkItems(planId)),
    );
    return _list(response.data).map(PlanWorkItemModel.fromJson).toList();
  }

  Future<void> createWorkItem(String planId, Map<String, dynamic> data) async {
    await _request(
      (client) => client.dio.post(Endpoints.planWorkItems(planId), data: data),
    );
  }

  Future<void> updateWorkItem(String itemId, Map<String, dynamic> data) async {
    await _request(
      (client) => client.dio.patch(Endpoints.planWorkItem(itemId), data: data),
    );
  }

  Future<void> deleteWorkItem(String itemId) async {
    await _request(
      (client) => client.dio.delete(Endpoints.planWorkItem(itemId)),
    );
  }

  Future<List<PlanCommentModel>> getComments(
    String planId, {
    String? activityId,
  }) async {
    final response = await _request(
      (client) => client.dio.get(
        Endpoints.planComments(planId),
        queryParameters: activityId == null
            ? null
            : {'activity_id': activityId},
      ),
    );
    return _list(response.data).map(PlanCommentModel.fromJson).toList();
  }

  Future<void> createComment(String planId, Map<String, dynamic> data) async {
    await _request(
      (client) => client.dio.post(Endpoints.planComments(planId), data: data),
    );
  }

  Future<void> react(String commentId, String? reaction) async {
    await _request(
      (client) => client.dio.post(
        Endpoints.planCommentReaction(commentId),
        data: {'reaction': reaction},
      ),
    );
  }

  Future<void> togglePin(String commentId) async {
    await _request(
      (client) => client.dio.post(Endpoints.planCommentPin(commentId)),
    );
  }

  Future<PlanModel> clonePlan(
    String planId, {
    required String title,
    required DateTime startDate,
    bool asTemplate = false,
  }) async {
    final response = await _request(
      (client) => client.dio.post(
        Endpoints.planClone(planId),
        data: {
          'title': title,
          'start_date': startDate.toUtc().toIso8601String(),
          'as_template': asTemplate,
        },
      ),
    );
    return PlanModel.fromJson(Map<String, dynamic>.from(response.data as Map));
  }

  Future<String> exportIcs(String planId) async {
    final response = await _request(
      (client) => client.dio.get<String>(
        Endpoints.planExportIcs(planId),
        options: Options(responseType: ResponseType.plain),
      ),
    );
    return response.data?.toString() ?? '';
  }

  Future<List<Map<String, dynamic>>> getCalendarLinks(String planId) async {
    final response = await _request(
      (client) => client.dio.get(Endpoints.planCalendarLinks(planId)),
    );
    final data = response.data is Map
        ? (response.data as Map)['results']
        : null;
    return _list(data);
  }

  Future<Response<dynamic>> _request(
    Future<Response<dynamic>> Function(ApiClient client) callback,
  ) async {
    try {
      return await _auth.requestWithAutoRefresh(callback);
    } on DioException catch (error) {
      if (error.response != null) throw buildApiException(error.response!);
      rethrow;
    }
  }

  List<Map<String, dynamic>> _list(dynamic value) =>
      (value as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
}
