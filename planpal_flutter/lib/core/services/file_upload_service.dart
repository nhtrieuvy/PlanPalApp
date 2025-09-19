import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as path;

/// File upload service with validation
class FileUploadService {
  final Dio _dio;

  FileUploadService(this._dio);

  /// Maximum file sizes (in bytes)
  static const int maxImageSize = 10 * 1024 * 1024; // 10MB
  static const int maxFileSize = 50 * 1024 * 1024; // 50MB

  /// Supported image formats
  static const List<String> supportedImageFormats = [
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
  ];

  /// Supported file formats
  static const List<String> supportedFileFormats = [
    '.pdf',
    '.doc',
    '.docx',
    '.xls',
    '.xlsx',
    '.ppt',
    '.pptx',
    '.txt',
    '.zip',
    '.rar',
    '.mp4',
    '.mp3',
    '.wav',
  ];

  /// Upload image with validation
  Future<FileUploadResult> uploadImage(
    File imageFile, {
    String folder = 'planpal/messages/attachments',
  }) async {
    try {
      // Validate file
      final validation = _validateImageFile(imageFile);
      if (!validation.isValid) {
        return FileUploadResult.error(validation.errorMessage!);
      }

      // Upload to Cloudinary
      final uploadResult = await _uploadToCloudinary(
        imageFile,
        folder: folder,
        resourceType: 'image',
      );

      return uploadResult;
    } catch (e) {
      return FileUploadResult.error('Failed to upload image: $e');
    }
  }

  /// Upload file with validation
  Future<FileUploadResult> uploadFile(
    File file, {
    String folder = 'planpal/messages/attachments',
  }) async {
    try {
      // Validate file
      final validation = _validateFile(file);
      if (!validation.isValid) {
        return FileUploadResult.error(validation.errorMessage!);
      }

      // Upload to Cloudinary
      return await _uploadToCloudinary(
        file,
        folder: folder,
        resourceType: 'auto',
      );
    } catch (e) {
      return FileUploadResult.error('Failed to upload file: $e');
    }
  }

  /// Validate image file
  FileValidation _validateImageFile(File file) {
    // Check if file exists
    if (!file.existsSync()) {
      return FileValidation.invalid('File does not exist');
    }

    // Check file size
    final fileSize = file.lengthSync();
    if (fileSize > maxImageSize) {
      return FileValidation.invalid(
        'Image size too large (max ${_formatFileSize(maxImageSize)})',
      );
    }

    // Check file extension
    final extension = path.extension(file.path).toLowerCase();
    if (!supportedImageFormats.contains(extension)) {
      return FileValidation.invalid(
        'Unsupported image format. Supported: ${supportedImageFormats.join(', ')}',
      );
    }

    return FileValidation.valid();
  }

  /// Validate file
  FileValidation _validateFile(File file) {
    // Check if file exists
    if (!file.existsSync()) {
      return FileValidation.invalid('File does not exist');
    }

    // Check file size
    final fileSize = file.lengthSync();
    if (fileSize > maxFileSize) {
      return FileValidation.invalid(
        'File size too large (max ${_formatFileSize(maxFileSize)})',
      );
    }

    // Check file extension
    final extension = path.extension(file.path).toLowerCase();
    final allSupportedFormats = [
      ...supportedImageFormats,
      ...supportedFileFormats,
    ];
    if (!allSupportedFormats.contains(extension)) {
      return FileValidation.invalid('Unsupported file format');
    }

    return FileValidation.valid();
  }

  /// Upload to Cloudinary
  Future<FileUploadResult> _uploadToCloudinary(
    File file, {
    required String folder,
    required String resourceType,
  }) async {
    try {
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path),
        'upload_preset': 'planpal_upload', // Configure this in Cloudinary
        'folder': folder,
        'resource_type': resourceType,
      });

      final response = await _dio.post(
        'https://api.cloudinary.com/v1_1/your_cloud_name/upload', // Configure your cloud name
        data: formData,
        options: Options(
          headers: {'Content-Type': 'multipart/form-data'},
          sendTimeout: const Duration(minutes: 2),
          receiveTimeout: const Duration(minutes: 2),
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        return FileUploadResult.success(
          url: data['secure_url'],
          publicId: data['public_id'],
          fileName: path.basename(file.path),
          fileSize: file.lengthSync(),
          mimeType: _getMimeType(file),
        );
      } else {
        return FileUploadResult.error(
          'Upload failed with status: ${response.statusCode}',
        );
      }
    } on DioException catch (e) {
      return FileUploadResult.error('Network error: ${e.message}');
    } catch (e) {
      return FileUploadResult.error('Unexpected error: $e');
    }
  }

  /// Get MIME type from file extension
  String _getMimeType(File file) {
    final extension = path.extension(file.path).toLowerCase();
    switch (extension) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.pdf':
        return 'application/pdf';
      case '.doc':
        return 'application/msword';
      case '.docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return 'application/octet-stream';
    }
  }

  /// Format file size for display
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

/// File validation result
class FileValidation {
  final bool isValid;
  final String? errorMessage;

  const FileValidation._(this.isValid, this.errorMessage);

  factory FileValidation.valid() => const FileValidation._(true, null);
  factory FileValidation.invalid(String message) =>
      FileValidation._(false, message);
}

/// File upload result
class FileUploadResult {
  final bool isSuccess;
  final String? url;
  final String? publicId;
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
  final String? errorMessage;

  const FileUploadResult._({
    required this.isSuccess,
    this.url,
    this.publicId,
    this.fileName,
    this.fileSize,
    this.mimeType,
    this.errorMessage,
  });

  factory FileUploadResult.success({
    required String url,
    required String publicId,
    required String fileName,
    required int fileSize,
    required String mimeType,
  }) => FileUploadResult._(
    isSuccess: true,
    url: url,
    publicId: publicId,
    fileName: fileName,
    fileSize: fileSize,
    mimeType: mimeType,
  );

  factory FileUploadResult.error(String message) =>
      FileUploadResult._(isSuccess: false, errorMessage: message);
}
