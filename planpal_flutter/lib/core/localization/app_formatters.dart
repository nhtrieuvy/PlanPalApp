import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_locale.dart';

class AppFormatters {
  static final Map<String, DateFormat> _dateFormatCache = {};
  static final Map<String, NumberFormat> _currencyFormatCache = {};

  static String localeTag(BuildContext context) {
    return AppLocaleStore.resolve(
      Localizations.localeOf(context),
    ).languageCode;
  }

  static String fullDateTime(BuildContext context, DateTime value) {
    return _dateFormat(
      localeTag(context),
      _fullDateTimePattern(localeTag(context)),
    ).format(value);
  }

  static String shortDate(BuildContext context, DateTime value) {
    return _dateFormat(
      localeTag(context),
      _shortDatePattern(localeTag(context)),
    ).format(value);
  }

  static String shortMonthDay(BuildContext context, DateTime value) {
    return _dateFormat(
      localeTag(context),
      _monthDayPattern(localeTag(context)),
    ).format(value);
  }

  static String notificationDateTime(BuildContext context, DateTime value) {
    return _dateFormat(
      localeTag(context),
      _notificationPattern(localeTag(context)),
    ).format(value);
  }

  static String shortTime(BuildContext context, DateTime value) {
    return _dateFormat(localeTag(context), 'HH:mm').format(value);
  }

  static String weekdayShort(BuildContext context, DateTime value) {
    return _dateFormat(localeTag(context), 'EEE').format(value);
  }

  static String currency(
    BuildContext context, {
    required double amount,
    required String currencyCode,
  }) {
    final locale = localeTag(context);
    final normalizedCode = currencyCode.toUpperCase();
    final symbol = normalizedCode == 'VND' ? '₫' : normalizedCode;
    final cacheKey = '$locale::$normalizedCode';
    final formatter = _currencyFormatCache.putIfAbsent(
      cacheKey,
      () => NumberFormat.currency(
        locale: locale,
        symbol: symbol,
        decimalDigits: normalizedCode == 'VND' ? 0 : 2,
      ),
    );
    return formatter.format(amount);
  }

  static DateFormat _dateFormat(String locale, String pattern) {
    final cacheKey = '$locale::$pattern';
    return _dateFormatCache.putIfAbsent(
      cacheKey,
      () => DateFormat(pattern, locale),
    );
  }

  static String _fullDateTimePattern(String locale) {
    return locale == 'vi' ? 'dd/MM/yyyy HH:mm' : 'MM/dd/yyyy HH:mm';
  }

  static String _shortDatePattern(String locale) {
    return locale == 'vi' ? 'dd/MM/yyyy' : 'MM/dd/yyyy';
  }

  static String _monthDayPattern(String locale) {
    return locale == 'vi' ? 'dd/MM' : 'MM/dd';
  }

  static String _notificationPattern(String locale) {
    return locale == 'vi' ? 'dd/MM HH:mm' : 'MM/dd HH:mm';
  }
}
