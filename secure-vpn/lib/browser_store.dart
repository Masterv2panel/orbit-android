// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class BrowserVisit {
  const BrowserVisit({required this.url, required this.title, required this.visitedAt});

  final String url;
  final String title;
  final DateTime visitedAt;

  Map<String, Object?> toJson() => {
        'url': url,
        'title': title,
        'visitedAt': visitedAt.toUtc().toIso8601String(),
      };

  static BrowserVisit? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final url = value['url'];
    final title = value['title'];
    final rawVisitedAt = value['visitedAt'];
    final visitedAt = DateTime.tryParse(rawVisitedAt is String ? rawVisitedAt : '');
    if (url is! String || url.isEmpty || title is! String || visitedAt == null) return null;
    return BrowserVisit(url: url, title: title, visitedAt: visitedAt.toLocal());
  }
}

class BrowserBookmark {
  const BrowserBookmark({required this.url, required this.title, required this.addedAt});

  final String url;
  final String title;
  final DateTime addedAt;

  Map<String, Object?> toJson() => {
        'url': url,
        'title': title,
        'addedAt': addedAt.toUtc().toIso8601String(),
      };

  static BrowserBookmark? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final url = value['url'];
    final title = value['title'];
    final rawAddedAt = value['addedAt'];
    final addedAt = DateTime.tryParse(rawAddedAt is String ? rawAddedAt : '');
    if (url is! String || url.isEmpty || title is! String || addedAt == null) return null;
    return BrowserBookmark(url: url, title: title, addedAt: addedAt.toLocal());
  }
}

class BrowserStore {
  BrowserStore._();

  static final BrowserStore instance = BrowserStore._();
  static const _historyKey = 'orbit_browser_history_v1';
  static const _bookmarksKey = 'orbit_browser_bookmarks_v1';
  static const _timezoneEnabledKey = 'orbit_timezone_lookup_enabled_v1';
  static const _timezonePromptShownKey = 'orbit_timezone_lookup_prompt_shown_v1';
  static const _thirdPartyCookiesKey = 'orbit_third_party_cookies_enabled_v1';
  static const maxHistoryEntries = 500;

  Future<SharedPreferences>? _preferencesFuture;

  Future<SharedPreferences> get _preferences =>
      _preferencesFuture ??= SharedPreferences.getInstance();

  Future<List<BrowserVisit>> loadHistory() async {
    final raw = (await _preferences).getString(_historyKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.map(BrowserVisit.fromJson).whereType<BrowserVisit>().toList();
    } on FormatException {
      return [];
    }
  }

  Future<List<BrowserBookmark>> loadBookmarks() async {
    final raw = (await _preferences).getString(_bookmarksKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.map(BrowserBookmark.fromJson).whereType<BrowserBookmark>().toList();
    } on FormatException {
      return [];
    }
  }

  Future<void> recordVisit({required String url, required String title}) async {
    final parsed = Uri.tryParse(url);
    if (parsed == null || !{'http', 'https'}.contains(parsed.scheme.toLowerCase())) return;
    final history = await loadHistory();
    history.insert(
      0,
      BrowserVisit(
        url: url,
        title: title.trim().isEmpty ? parsed.host : title.trim(),
        visitedAt: DateTime.now(),
      ),
    );
    final limited = history.take(maxHistoryEntries).map((entry) => entry.toJson()).toList();
    await (await _preferences).setString(_historyKey, jsonEncode(limited));
  }

  Future<bool> isBookmarked(String url) async =>
      (await loadBookmarks()).any((bookmark) => bookmark.url == url);

  Future<bool> timezoneLookupEnabled() async =>
      (await _preferences).getBool(_timezoneEnabledKey) ?? false;

  Future<void> setTimezoneLookupEnabled(bool enabled) async {
    await (await _preferences).setBool(_timezoneEnabledKey, enabled);
  }

  Future<bool> timezonePromptShown() async =>
      (await _preferences).getBool(_timezonePromptShownKey) ?? false;

  Future<void> setTimezonePromptShown() async {
    await (await _preferences).setBool(_timezonePromptShownKey, true);
  }

  Future<bool> thirdPartyCookiesEnabled() async =>
      (await _preferences).getBool(_thirdPartyCookiesKey) ?? false;

  Future<void> setThirdPartyCookiesEnabled(bool enabled) async {
    await (await _preferences).setBool(_thirdPartyCookiesKey, enabled);
  }

  Future<bool> toggleBookmark({required String url, required String title}) async {
    final bookmarks = await loadBookmarks();
    final existing = bookmarks.indexWhere((bookmark) => bookmark.url == url);
    if (existing >= 0) {
      bookmarks.removeAt(existing);
      await _writeBookmarks(bookmarks);
      return false;
    }
    final parsed = Uri.tryParse(url);
    if (parsed == null || !{'http', 'https'}.contains(parsed.scheme.toLowerCase())) return false;
    bookmarks.insert(
      0,
      BrowserBookmark(
        url: url,
        title: title.trim().isEmpty ? parsed.host : title.trim(),
        addedAt: DateTime.now(),
      ),
    );
    await _writeBookmarks(bookmarks);
    return true;
  }

  Future<void> removeBookmark(String url) async {
    final bookmarks = await loadBookmarks();
    bookmarks.removeWhere((bookmark) => bookmark.url == url);
    await _writeBookmarks(bookmarks);
  }

  Future<void> removeVisit(BrowserVisit visit) async {
    final history = await loadHistory();
    history.removeWhere((entry) =>
        entry.url == visit.url && entry.visitedAt.isAtSameMomentAs(visit.visitedAt));
    await _writeHistory(history);
  }

  Future<void> clearHistory() async {
    await (await _preferences).remove(_historyKey);
  }

  Future<void> clearBookmarks() async {
    await (await _preferences).remove(_bookmarksKey);
  }

  Future<void> clearLibrary() async {
    final preferences = await _preferences;
    await preferences.remove(_historyKey);
    await preferences.remove(_bookmarksKey);
  }

  Future<void> _writeBookmarks(List<BrowserBookmark> bookmarks) async {
    await (await _preferences).setString(
      _bookmarksKey,
      jsonEncode(bookmarks.map((bookmark) => bookmark.toJson()).toList()),
    );
  }

  Future<void> _writeHistory(List<BrowserVisit> history) async {
    await (await _preferences).setString(
      _historyKey,
      jsonEncode(history.map((visit) => visit.toJson()).toList()),
    );
  }
}
