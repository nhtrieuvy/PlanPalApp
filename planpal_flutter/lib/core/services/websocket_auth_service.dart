import 'package:flutter/foundation.dart';

import 'apis.dart';

/// Builds WebSocket authentication parameters without exposing bearer tokens
/// in browser URLs. Native clients keep the existing contract during rollout.
Future<String> webSocketAuthQuery(String accessToken) async {
  if (!kIsWeb) {
    return 'token=${Uri.encodeQueryComponent(accessToken)}';
  }

  final response = await ApiClient(
    token: accessToken,
  ).dio.post(Endpoints.websocketTicket);
  final data = response.data;
  if (data is! Map || data['ticket']?.toString().isEmpty != false) {
    throw StateError('WebSocket ticket response is invalid.');
  }
  return 'ticket=${Uri.encodeQueryComponent(data['ticket'].toString())}';
}
