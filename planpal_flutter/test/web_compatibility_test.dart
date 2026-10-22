import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:planpal_flutter/core/files/safe_file_name.dart';
import 'package:planpal_flutter/core/files/upload_file.dart';
import 'package:planpal_flutter/core/services/apis.dart';

void main() {
  test('feature endpoints keep the versioned API contract', () {
    final endpoints = <String>[
      Endpoints.register,
      Endpoints.verifyEmail,
      Endpoints.resendEmailVerification,
      Endpoints.groupInvites('group-id'),
      Endpoints.groupJoinCode,
      Endpoints.plans,
      Endpoints.activities,
      Endpoints.groupPolls('group-id'),
      Endpoints.planWorkItems('plan-id'),
      Endpoints.planComments('plan-id'),
      Endpoints.conversations,
      Endpoints.websocketTicket,
      Endpoints.planExpenses('plan-id'),
      Endpoints.planBalances('plan-id'),
      Endpoints.locationReverseGeocode,
      Endpoints.auditLogs,
      Endpoints.analyticsSummary,
      Endpoints.planExportIcs('plan-id'),
    ];

    expect(endpoints, everyElement(startsWith('/api/v1/')));
  });

  test('browser-backed XFile can be streamed into multipart upload', () async {
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final file = XFile.fromData(bytes, name: 'receipt.png');

    // VM-backed XFile does not retain the browser-provided name, so callers
    // can pass the original picker name explicitly through the shared API.
    final multipart = await multipartFromXFile(file, filename: 'receipt.png');
    final uploaded = await multipart.finalize().fold<List<int>>(
      <int>[],
      (buffer, chunk) => buffer..addAll(chunk),
    );

    expect(multipart.filename, 'receipt.png');
    expect(uploaded, bytes);
  });

  test('ICS filenames are portable across browser and native downloads', () {
    expect(
      safeFileName('Trip: Da Nang / 2026?', fallback: 'planpal-plan'),
      'Trip_ Da Nang _ 2026_',
    );
    expect(safeFileName(' . ', fallback: 'planpal-plan'), 'planpal-plan');
  });
}
