import 'package:cross_file/cross_file.dart';
import 'package:dio/dio.dart';

/// Creates a multipart body from an [XFile] without relying on `dart:io`.
///
/// `openRead` works for native files and browser-backed blobs, so repositories
/// can expose the same upload contract on Android, iOS and Web.
Future<MultipartFile> multipartFromXFile(XFile file, {String? filename}) async {
  final length = await file.length();
  final resolvedName = filename?.trim().isNotEmpty == true
      ? filename!.trim()
      : file.name.trim().isNotEmpty
      ? file.name.trim()
      : 'upload.bin';
  return MultipartFile.fromStream(
    file.openRead,
    length,
    filename: resolvedName,
  );
}
