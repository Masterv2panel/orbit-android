// SPDX-License-Identifier: GPL-3.0-or-later

enum BrowserBackAction { webHistory, closeTab, home, exit }

/// Priority for Android Back: web history, then another tab, then browser home,
/// and only then the platform may leave the app.
BrowserBackAction browserBackAction({
  required bool webCanGoBack,
  required int tabCount,
  required bool isHome,
}) {
  if (webCanGoBack) return BrowserBackAction.webHistory;
  if (tabCount > 1) return BrowserBackAction.closeTab;
  if (!isHome) return BrowserBackAction.home;
  return BrowserBackAction.exit;
}
