void main() {
  // Test URL validation like in User model
  bool isValidImageUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.isAbsolute &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  final testUrl =
      'https://res.cloudinary.com/dd0q3guu9/image/upload/v1/planpal/avatars/d6m9mj0nziyweraqklx9';
  print('URL: $testUrl');
  print('Valid: ${isValidImageUrl(testUrl)}');

  final uri = Uri.tryParse(testUrl);
  print('Parsed URI: $uri');
  print('Scheme: ${uri?.scheme}');
  print('Is absolute: ${uri?.isAbsolute}');
}
