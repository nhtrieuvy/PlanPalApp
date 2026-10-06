String safeFileName(String value, {required String fallback}) {
  final sanitized = value
      .trim()
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[. ]+$'), '');
  return sanitized.isEmpty ? fallback : sanitized;
}
