import 'package:dio/dio.dart';
import 'package:planpal_flutter/core/auth/auth_session.dart';
import 'package:planpal_flutter/core/dtos/experience_models.dart';
import 'package:planpal_flutter/core/services/api_error.dart';
import 'package:planpal_flutter/core/services/apis.dart';
import 'package:planpal_flutter/core/services/offline_sync_service.dart';

class ExperienceRepository {
  ExperienceRepository(this._auth, this._offlineSync);

  final AuthProvider _auth;
  final OfflineSyncService _offlineSync;

  Future<GlobalSearchResult> search(String query, {int limit = 8}) async {
    final response = await _request(
      (client) => client.dio.get(
        Endpoints.globalSearch,
        queryParameters: {'q': query, 'limit': limit},
      ),
    );
    return GlobalSearchResult.fromJson(
      Map<String, dynamic>.from(response.data as Map),
    );
  }

  Future<List<GroupPollModel>> getPolls(String groupId) async {
    final response = await _request(
      (client) => client.dio.get(Endpoints.groupPolls(groupId)),
    );
    return _models(response.data, GroupPollModel.fromJson);
  }

  Future<GroupPollModel?> createPoll(
    String groupId,
    Map<String, dynamic> data,
  ) => _queueableModel(
    method: 'POST',
    path: Endpoints.groupPolls(groupId),
    data: data,
    decode: GroupPollModel.fromJson,
  );

  Future<GroupPollModel?> vote(String pollId, Set<String> optionIds) =>
      _queueableModel(
        method: 'POST',
        path: Endpoints.groupPollVote(pollId),
        data: {'option_ids': optionIds.toList()},
        decode: GroupPollModel.fromJson,
      );

  Future<GroupPollModel?> closePoll(String pollId) => _queueableModel(
    method: 'POST',
    path: Endpoints.groupPollClose(pollId),
    data: const {},
    decode: GroupPollModel.fromJson,
  );

  Future<List<LiveLocationModel>> getLiveLocations(
    String conversationId,
  ) async {
    final response = await _request(
      (client) =>
          client.dio.get(Endpoints.conversationLiveLocations(conversationId)),
    );
    return _models(response.data, LiveLocationModel.fromJson);
  }

  Future<LiveLocationModel?> startLiveLocation(
    String conversationId,
    Map<String, dynamic> data,
  ) => _queueableModel(
    method: 'POST',
    path: Endpoints.conversationLiveLocations(conversationId),
    data: data,
    decode: LiveLocationModel.fromJson,
  );

  Future<LiveLocationModel?> updateLiveLocation(
    String shareId,
    Map<String, dynamic> data,
  ) => _queueableModel(
    method: 'PATCH',
    path: Endpoints.liveLocation(shareId),
    data: data,
    decode: LiveLocationModel.fromJson,
  );

  Future<void> stopLiveLocation(String shareId) async {
    await _queueable(
      method: 'DELETE',
      path: Endpoints.liveLocation(shareId),
      data: const {},
    );
  }

  Future<T?> _queueableModel<T>({
    required String method,
    required String path,
    required Map<String, dynamic> data,
    required T Function(Map<String, dynamic>) decode,
  }) async {
    final response = await _queueable(method: method, path: path, data: data);
    if (response == null || response.data is! Map) return null;
    return decode(Map<String, dynamic>.from(response.data as Map));
  }

  Future<Response<dynamic>?> _queueable({
    required String method,
    required String path,
    required Map<String, dynamic> data,
  }) async {
    final mutationId = _offlineSync.newMutationId();
    try {
      return await _request(
        (client) => client.dio.request<dynamic>(
          path,
          data: data,
          options: Options(
            method: method,
            headers: {'X-Client-Mutation-ID': mutationId},
          ),
        ),
      );
    } on DioException catch (error) {
      if (error.response != null) rethrow;
      await _offlineSync.enqueue(
        id: mutationId,
        method: method,
        path: path,
        data: data,
      );
      return null;
    }
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

  List<T> _models<T>(dynamic data, T Function(Map<String, dynamic>) decode) =>
      (data as List? ?? const [])
          .whereType<Map>()
          .map((item) => decode(Map<String, dynamic>.from(item)))
          .toList();
}
