import 'package:flutter/material.dart';

enum AppLanguage {
  vietnamese('vi'),
  english('en');

  final String code;
  const AppLanguage(this.code);

  Locale get locale => Locale(code);
}

class AppLocaleStore {
  static const Locale fallbackLocale = Locale('vi');
  static const List<Locale> supportedLocales = [
    Locale('vi'),
    Locale('en'),
  ];

  static Locale _currentLocale = fallbackLocale;

  static Locale get currentLocale => _currentLocale;

  static String get currentLanguageCode => _currentLocale.languageCode;

  static void setCurrentLocale(Locale locale) {
    _currentLocale = resolve(locale);
  }

  static Locale resolve(Locale locale) {
    for (final supported in supportedLocales) {
      if (supported.languageCode == locale.languageCode) {
        return supported;
      }
    }
    return fallbackLocale;
  }

  static Locale fromLanguageCode(String? code) {
    if (code == null || code.isEmpty) {
      return fallbackLocale;
    }
    return resolve(Locale(code));
  }

  static Locale resolveDeviceLocale(Locale? locale) {
    if (locale == null) {
      return fallbackLocale;
    }
    return resolve(locale);
  }

  static AppLanguage get currentLanguage =>
      currentLanguageCode == AppLanguage.english.code
      ? AppLanguage.english
      : AppLanguage.vietnamese;
}
