// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:orbit_secure/app_locale_controller.dart';
import 'package:orbit_secure/browser_navigation_policy.dart';

void main() {
  group('browserBackAction', () {
    test('prefers WebView history over closing a tab', () {
      expect(
        browserBackAction(webCanGoBack: true, tabCount: 4, isHome: false),
        BrowserBackAction.webHistory,
      );
    });

    test('closes the current tab when no WebView history remains', () {
      expect(
        browserBackAction(webCanGoBack: false, tabCount: 2, isHome: false),
        BrowserBackAction.closeTab,
      );
    });

    test('returns a single remaining tab to home before exit', () {
      expect(
        browserBackAction(webCanGoBack: false, tabCount: 1, isHome: false),
        BrowserBackAction.home,
      );
    });

    test('allows exit only from home in the final tab', () {
      expect(
        browserBackAction(webCanGoBack: false, tabCount: 1, isHome: true),
        BrowserBackAction.exit,
      );
    });
  });

  group('OrbitLocaleController', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test(
      'defaults to Persian and persists English between instances',
      () async {
        final first = OrbitLocaleController();
        await first.load();
        expect(first.locale.languageCode, 'fa');
        await first.setLanguage('en');
        expect(first.locale.languageCode, 'en');
        first.dispose();

        final second = OrbitLocaleController();
        await second.load();
        expect(second.locale.languageCode, 'en');
        second.dispose();
      },
    );
  });
}
