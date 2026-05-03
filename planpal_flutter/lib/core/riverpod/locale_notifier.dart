import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/app_locale.dart';
import 'storage_providers.dart';

class LocaleNotifier extends Notifier<Locale> {
  static const String _storageKey = 'app_locale_code';

  @override
  Locale build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final savedCode = prefs.getString(_storageKey);
    final resolvedLocale = savedCode != null
        ? AppLocaleStore.fromLanguageCode(savedCode)
        : AppLocaleStore.resolveDeviceLocale(
            WidgetsBinding.instance.platformDispatcher.locale,
          );
    AppLocaleStore.setCurrentLocale(resolvedLocale);
    return resolvedLocale;
  }

  Future<void> setLanguage(AppLanguage language) {
    return setLocale(language.locale);
  }

  Future<void> setLocale(Locale locale) async {
    final resolved = AppLocaleStore.resolve(locale);
    if (state == resolved) {
      AppLocaleStore.setCurrentLocale(resolved);
      return;
    }
    state = resolved;
    AppLocaleStore.setCurrentLocale(resolved);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_storageKey, resolved.languageCode);
  }
}

final localeNotifierProvider = NotifierProvider<LocaleNotifier, Locale>(
  LocaleNotifier.new,
);

final currentAppLanguageProvider = Provider<AppLanguage>((ref) {
  final locale = ref.watch(localeNotifierProvider);
  return locale.languageCode == AppLanguage.english.code
      ? AppLanguage.english
      : AppLanguage.vietnamese;
});
