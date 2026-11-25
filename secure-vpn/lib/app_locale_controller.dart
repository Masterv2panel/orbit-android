// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the app-wide language choice without changing the device language.
class OrbitLocaleController extends ChangeNotifier {
  static const _preferenceKey = 'orbit_ui_language_v1';

  Locale _locale = const Locale('fa', 'IR');
  int _changeCount = 0;
  Locale get locale => _locale;
  bool get isEnglish => _locale.languageCode == 'en';

  Future<void> load() async {
    final changeCountAtStart = _changeCount;
    try {
      final saved = (await SharedPreferences.getInstance()).getString(
        _preferenceKey,
      );
      if (changeCountAtStart != _changeCount) return;
      _locale = saved == 'en'
          ? const Locale('en', 'US')
          : const Locale('fa', 'IR');
      notifyListeners();
    } catch (_) {
      // Keep the usable Persian default if local preferences are unavailable.
    }
  }

  Future<void> toggle() async {
    await setLanguage(isEnglish ? 'fa' : 'en');
  }

  Future<void> setLanguage(String languageCode) async {
    if (languageCode != 'fa' && languageCode != 'en') {
      throw ArgumentError.value(
        languageCode,
        'languageCode',
        'Only fa and en are supported.',
      );
    }
    final next = languageCode == 'en'
        ? const Locale('en', 'US')
        : const Locale('fa', 'IR');
    if (next == _locale) return;
    _changeCount++;
    _locale = next;
    notifyListeners();
    await (await SharedPreferences.getInstance()).setString(
      _preferenceKey,
      languageCode,
    );
  }
}
