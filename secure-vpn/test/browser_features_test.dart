// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_secure/browser_store.dart';
import 'package:orbit_secure/vpn_timezone_service.dart';

void main() {
  group('Browser library records', () {
    test('history records round-trip in UTC without changing the URL', () {
      final visit = BrowserVisit(
        url: 'https://example.com/path?q=1',
        title: 'Example',
        visitedAt: DateTime.utc(2026, 11, 26, 10, 15),
      );
      final decoded = jsonDecode(jsonEncode(visit.toJson()));
      final restored = BrowserVisit.fromJson(decoded);
      expect(restored, isNotNull);
      expect(restored!.url, visit.url);
      expect(restored.title, visit.title);
      expect(restored.visitedAt.toUtc(), visit.visitedAt);
    });

    test('invalid records are ignored instead of crashing the browser', () {
      expect(BrowserBookmark.fromJson({'url': '', 'title': 'x', 'addedAt': 'broken'}), isNull);
      expect(BrowserBookmark.fromJson({'url': 'https://example.com', 'title': 'x', 'addedAt': 42}), isNull);
      expect(BrowserVisit.fromJson('not a record'), isNull);
      expect(BrowserVisit.fromJson({'url': 'https://example.com', 'title': 'x', 'visitedAt': false}), isNull);
    });
  });

  group('VPN timezone script', () {
    final service = VpnTimezoneService();

    test('targets common browser timezone APIs without changing system settings', () {
      final script = service.buildDocumentStartScript('America/Los_Angeles');
      expect(script, contains('America/Los_Angeles'));
      expect(script, contains('Intl, \'DateTimeFormat\''));
      expect(script, contains('getTimezoneOffset'));
      expect(script, contains('__orbitVpnTimezone'));
      expect(script, isNot(contains('Settings.Global')));
    });

    test('rejects malformed zone identifiers before script creation', () {
      expect(() => service.buildDocumentStartScript('not a time zone'), throwsFormatException);
    });
  });
}
