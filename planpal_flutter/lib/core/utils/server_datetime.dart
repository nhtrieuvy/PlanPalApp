DateTime? parseServerDateTime(dynamic value) {
  if (value == null) return null;

  final raw = value.toString().trim();
  if (raw.isEmpty) return null;

  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;

  return parsed.toLocal();
}
