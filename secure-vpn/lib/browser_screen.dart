// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'browser_library_screen.dart';
import 'browser_navigation_policy.dart';
import 'browser_store.dart';
import 'orbit_localization.dart';
import 'security_guide_screen.dart';
import 'vpn_service.dart';
import 'vpn_timezone_service.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key, this.onOpenVpn, this.onToggleLocale});

  final ValueChanged<BuildContext>? onOpenVpn;
  final VoidCallback? onToggleLocale;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  // Keep every live WebView's navigation stack intact; cap native renderers
  // rather than silently evicting inactive tabs.
  static const _maxTabs = 4;
  static const _accent = Color(0xFF52E6DF);

  final _addressController = TextEditingController();
  final _findController = TextEditingController();
  final _vpnService = OrbitVpnService.instance;
  final _store = BrowserStore.instance;
  final _timezoneService = VpnTimezoneService();
  final List<_BrowserTab> _tabs = [_BrowserTab(0)];

  StreamSubscription<dynamic>? _vpnSubscription;
  Future<void>? _timezoneTask;
  int _activeTabIndex = 0;
  int _nextTabId = 1;
  String _vpnState = 'checking';
  String? _timezone;
  String? _timezoneError;
  String? _error;
  bool _ready = false;
  bool _timezoneBusy = false;
  bool _timezoneLookupEnabled = false;
  bool _thirdPartyCookiesEnabled = false;
  bool _showFindBar = false;
  bool _isBookmarked = false;
  bool _handlingSystemBack = false;

  _BrowserTab get _activeTab => _tabs[_activeTabIndex];
  bool get _canExitFromCurrentTab =>
      browserBackAction(
        webCanGoBack: _activeTab.canGoBack,
        tabCount: _tabs.length,
        isHome: _activeTab.initialUrl == null && !_activeTab.rendererGone,
      ) ==
      BrowserBackAction.exit;

  @override
  void initState() {
    super.initState();
    unawaited(_loadBrowserPreferences());
    unawaited(_initializeVpnStatus());
  }

  Future<void> _loadBrowserPreferences() async {
    try {
      final timezoneEnabled = await _store.timezoneLookupEnabled();
      final thirdPartyCookies = await _store.thirdPartyCookiesEnabled();
      if (!mounted) return;
      setState(() {
        _timezoneLookupEnabled = timezoneEnabled;
        _thirdPartyCookiesEnabled = thirdPartyCookies;
      });
    } catch (_) {
      // Use the privacy-preserving defaults if local preferences cannot be read.
    }
  }

  Future<void> _initializeVpnStatus() async {
    try {
      await _vpnService.initialize();
      _vpnSubscription = _vpnService.api.status.listen((status) {
        _updateVpnState(status.state.toString().split('.').last);
      });
      final status = await _vpnService.api.getStatus();
      if (!mounted) return;
      setState(() => _ready = true);
      _updateVpnState(status.state.toString().split('.').last);
    } catch (_) {
      if (mounted) setState(() => _ready = true);
      _updateVpnState('disconnected');
    }
  }

  void _updateVpnState(String nextState) {
    final previous = _vpnState;
    if (mounted) setState(() => _vpnState = nextState);
    if (nextState == 'connected' && previous != 'connected') {
      _timezone = null;
      _timezoneError = null;
      _timezoneTask = _prepareTimezoneLookup();
    } else if (previous == 'connected' && nextState != 'connected') {
      _timezone = null;
      _timezoneError = null;
      unawaited(_lockTabsAfterDisconnect());
    }
  }

  Future<void> _prepareTimezoneLookup() async {
    var enabled = await _store.timezoneLookupEnabled();
    if (!mounted || _vpnState != 'connected') return;
    if (!enabled && !await _store.timezonePromptShown()) {
      await _store.setTimezonePromptShown();
      enabled =
          await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: Text(orbitText(context, 'هماهنگ‌سازی timezone مرورگر؟')),
              content: Text(
                orbitText(
                  context,
                  'برای برآورد منطقهٔ زمانی، Orbit یک درخواست HTTPS به ipapi.co می‌فرستد. این سرویس IP خروجی VPN را دریافت می‌کند. '
                  'تنظیم فقط روی JavaScript مرورگر اثر می‌گذارد، نه ساعت Android، و ممکن است در WebViewهای قدیمی دیر اعمال شود.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(orbitText(context, 'فعلاً نه')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(orbitText(context, 'فعال‌سازی')),
                ),
              ],
            ),
          ) ??
          false;
      await _store.setTimezoneLookupEnabled(enabled);
    }
    if (!mounted || _vpnState != 'connected') return;
    setState(() => _timezoneLookupEnabled = enabled);
    if (enabled) {
      await _lookupTimezone();
    } else {
      setState(
        () => _timezoneError = 'درخواست بیرونی timezone غیرفعال است؛ از timezone دستگاه استفاده می‌شود.',
      );
    }
  }

  Future<void> _lookupTimezone() async {
    if (_vpnState != 'connected') return;
    if (mounted) setState(() => _timezoneBusy = true);
    try {
      final zone = await _timezoneService.lookupExitTimezone();
      if (!mounted || _vpnState != 'connected') return;
      setState(() {
        _timezone = zone;
        _timezoneError = null;
      });
      await _reloadOpenTabsForTimezone();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _timezone = null;
        _timezoneError = 'منطقهٔ زمانی VPN دریافت نشد؛ از منطقهٔ زمانی دستگاه استفاده می‌شود.';
      });
    } finally {
      if (mounted) setState(() => _timezoneBusy = false);
      _timezoneTask = null;
    }
  }

  Future<void> _ensureTimezoneLookup() async {
    if (_vpnState != 'connected' || _timezone != null || _timezoneError != null)
      return;
    final pending = _timezoneTask;
    if (pending != null) {
      await pending;
    } else {
      final task = _prepareTimezoneLookup();
      _timezoneTask = task;
      await task;
    }
  }

  Future<void> _editTimezonePreference() async {
    final enabled = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(orbitText(context, 'منطقهٔ زمانی خروجی VPN')),
        content: Text(
          orbitText(
            context,
            'هنگام فعال‌بودن، ipapi.co درخواست دریافت می‌کند و IP خروجی VPN را می‌بیند. '
            'در صورت خاموش‌کردن، صفحات جدید از timezone دستگاه استفاده می‌کنند.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(orbitText(context, 'خاموش و استفاده از دستگاه')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(orbitText(context, 'فعال‌سازی / تلاش دوباره')),
          ),
        ],
      ),
    );
    if (enabled == null) return;
    await _store.setTimezonePromptShown();
    await _store.setTimezoneLookupEnabled(enabled);
    if (!mounted) return;
    setState(() {
      _timezoneLookupEnabled = enabled;
      _timezone = null;
      _timezoneError = enabled ? null : 'درخواست بیرونی timezone غیرفعال است؛ از timezone دستگاه استفاده می‌شود.';
    });
    if (enabled && _vpnState == 'connected') {
      final task = _lookupTimezone();
      _timezoneTask = task;
      await task;
    } else {
      await _reloadOpenTabsForTimezone();
    }
  }

  Future<void> _reloadOpenTabsForTimezone() async {
    for (final tab in _tabs) {
      final controller = tab.controller;
      if (tab.currentUrl == null || controller == null || tab.rendererGone)
        continue;
      try {
        await controller.removeUserScriptsByGroupName(
          groupName: 'orbit-vpn-timezone',
        );
        final timezone = _timezone;
        if (timezone != null) {
          await controller.addUserScript(
            userScript: UserScript(
              groupName: 'orbit-vpn-timezone',
              source: _timezoneService.buildDocumentStartScript(timezone),
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              forMainFrameOnly: true,
            ),
          );
        }
        // reload() retains the WebView's back/forward list; replacing the
        // widget/controller here would silently discard that history.
        await controller.reload();
      } catch (_) {
        // A renderer may have failed while updating the script or reloading.
      }
    }
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _toggleThirdPartyCookies() async {
    final enable = !_thirdPartyCookiesEnabled;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              orbitText(
                context,
                enable
                    ? 'فعال‌کردن کوکی شخص ثالث؟'
                    : 'مسدودکردن کوکی شخص ثالث؟',
              ),
            ),
            content: Text(
              orbitText(
                context,
                enable
                    ? 'این کار ممکن است ورود یا پرداخت بعضی سایت‌ها را بهتر کند، اما سرویس‌های تعبیه‌شده می‌توانند کوکی بین‌سایتی داشته باشند.'
                    : 'با مسدودکردن، حریم خصوصی بهتر می‌شود؛ ورود یکپارچه یا برخی امکانات سایت ممکن است از کار بیفتد.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(orbitText(context, 'انصراف')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(orbitText(context, 'تأیید')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    await _store.setThirdPartyCookiesEnabled(enable);
    if (!mounted) return;
    setState(() => _thirdPartyCookiesEnabled = enable);
    for (final tab in _tabs) {
      try {
        await tab.controller?.setSettings(
          settings: InAppWebViewSettings(thirdPartyCookiesEnabled: enable),
        );
      } catch (_) {
        // New tabs will use the saved setting even if a live WebView rejects it.
      }
    }
  }

  Future<void> _lockTabsAfterDisconnect() async {
    for (final tab in _tabs) {
      final controller = tab.controller;
      if (controller != null) {
        try {
          await controller.stopLoading();
          await controller.loadUrl(
            urlRequest: URLRequest(url: WebUri('about:blank')),
          );
        } catch (_) {
          // System-level Android lockdown is still needed for disconnect races.
        }
      }
      tab.controller = null;
      tab.initialUrl = null;
      tab.currentUrl = null;
      tab.title = 'زبانهٔ جدید';
      tab.isLoading = false;
      tab.progress = 0;
      tab.canGoBack = false;
      tab.canGoForward = false;
    }
    if (!mounted) return;
    _addressController.clear();
    setState(() {
      _error = 'VPN قطع شد؛ صفحات برای جلوگیری از ادامهٔ بارگذاری بسته شدند.';
      _isBookmarked = false;
    });
  }

  Uri? _destinationFor(String input) {
    final value = input.trim();
    if (value.isEmpty) return null;
    if (value.contains(RegExp(r'\s'))) {
      return Uri.https('duckduckgo.com', '/', {'q': value});
    }
    final candidate = value.contains('://') ? value : 'https://$value';
    final uri = Uri.tryParse(candidate);
    if (uri == null ||
        uri.host.isEmpty ||
        !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      return null;
    }
    return uri;
  }

  Future<void> _openAddress([String? raw]) =>
      _openAddressInTab(_activeTab, raw ?? _addressController.text);

  Future<void> _openAddressInTab(_BrowserTab tab, String input) async {
    if (_vpnState != 'connected') {
      if (mounted)
        setState(
          () =>
              _error = 'قفل مرورگر فعال است؛ برای وب‌گردی ابتدا VPN را وصل کن.',
        );
      return;
    }
    final uri = _destinationFor(input);
    if (uri == null) {
      if (mounted)
        setState(
          () => _error = 'نشانی معتبر HTTP/HTTPS یا عبارت جست‌وجو وارد کن.',
        );
      return;
    }

    FocusScope.of(context).unfocus();
    await _ensureTimezoneLookup();
    if (!mounted || _vpnState != 'connected') return;

    setState(() {
      _error = null;
      tab.isLoading = true;
      tab.progress = 0;
      tab.currentUrl = uri.toString();
      if (tab.controller == null) {
        tab.initialUrl = uri.toString();
        tab.title = uri.host;
      }
      if (identical(tab, _activeTab)) _addressController.text = uri.toString();
    });
    try {
      final controller = tab.controller;
      if (controller != null) {
        await controller.loadUrl(
          urlRequest: URLRequest(url: WebUri(uri.toString())),
        );
      }
    } catch (_) {
      if (mounted)
        setState(() {
          tab.isLoading = false;
          _error = 'بارگذاری شروع نشد. نشانی یا اتصال VPN را بررسی کن.';
        });
    }
  }

  Future<void> _onPageFinished(
    _BrowserTab tab,
    InAppWebViewController controller,
    WebUri? reportedUrl,
  ) async {
    if (!mounted ||
        _vpnState != 'connected' ||
        !_tabs.contains(tab) ||
        !identical(tab.controller, controller))
      return;
    String? currentUrl;
    String? title;
    try {
      currentUrl =
          (await controller.getUrl())?.toString() ?? reportedUrl?.toString();
      title = (await controller.getTitle())?.trim();
    } catch (_) {
      // The renderer may disappear while a load-stop callback is in flight.
      return;
    }
    if (!mounted ||
        !_tabs.contains(tab) ||
        !identical(tab.controller, controller))
      return;
    final resolvedUrl = currentUrl;
    if (resolvedUrl == null || resolvedUrl == 'about:blank') {
      setState(() {
        tab.isLoading = false;
        tab.progress = 100;
      });
      return;
    }
    final parsed = Uri.tryParse(resolvedUrl);
    final safeTitle = (title == null || title.isEmpty)
        ? (parsed?.host ?? resolvedUrl)
        : title;
    tab.currentUrl = resolvedUrl;
    tab.title = safeTitle;
    tab.isLoading = false;
    tab.progress = 100;
    await _store.recordVisit(url: resolvedUrl, title: safeTitle);
    await _refreshTabNavigation(tab, controller);
    if (!mounted) return;
    setState(() {
      if (identical(tab, _activeTab)) _addressController.text = resolvedUrl;
    });
    if (identical(tab, _activeTab)) unawaited(_refreshBookmarkStatus());
  }

  Future<void> _refreshTabNavigation(
    _BrowserTab tab,
    InAppWebViewController controller,
  ) async {
    try {
      final canGoBack = await controller.canGoBack();
      final canGoForward = await controller.canGoForward();
      if (!mounted ||
          !_tabs.contains(tab) ||
          !identical(tab.controller, controller))
        return;
      setState(() {
        tab.canGoBack = canGoBack;
        tab.canGoForward = canGoForward;
      });
    } catch (_) {
      // Navigation may be changing while its back-forward state is queried.
    }
  }

  Future<void> _refreshBookmarkStatus() async {
    final url = _activeTab.currentUrl;
    final saved = url == null ? false : await _store.isBookmarked(url);
    if (mounted) setState(() => _isBookmarked = saved);
  }

  Future<void> _toggleBookmark() async {
    final url = _activeTab.currentUrl;
    if (url == null) return;
    final saved = await _store.toggleBookmark(
      url: url,
      title: _activeTab.title,
    );
    if (mounted) setState(() => _isBookmarked = saved);
  }

  Future<void> _goBack() async {
    final controller = _activeTab.controller;
    if (controller != null && await controller.canGoBack())
      await controller.goBack();
  }

  Future<void> _goForward() async {
    final controller = _activeTab.controller;
    if (controller != null && await controller.canGoForward())
      await controller.goForward();
  }

  Future<void> _handleSystemBack() async {
    if (_handlingSystemBack) return;
    _handlingSystemBack = true;
    try {
      final tab = _activeTab;
      final controller = tab.controller;
      var webCanGoBack = false;
      if (controller != null) {
        try {
          webCanGoBack = await controller.canGoBack();
        } catch (_) {
          // Renderer teardown may race with an Android Back event.
        }
      }
      if (!mounted) return;
      final action = browserBackAction(
        webCanGoBack: webCanGoBack,
        tabCount: _tabs.length,
        isHome: tab.initialUrl == null && !tab.rendererGone,
      );
      switch (action) {
        case BrowserBackAction.webHistory:
          try {
            await controller?.goBack();
            if (mounted &&
                controller != null &&
                identical(tab.controller, controller)) {
              await _refreshTabNavigation(tab, controller);
            }
          } catch (_) {
            if (mounted && tab.rendererGone) await _goHome();
          }
          break;
        case BrowserBackAction.closeTab:
          _closeTab(_activeTabIndex);
          break;
        case BrowserBackAction.home:
          await _goHome();
          break;
        case BrowserBackAction.exit:
          await SystemNavigator.pop();
          break;
      }
    } finally {
      _handlingSystemBack = false;
    }
  }

  Future<void> _goHome() => _goHomeForTab(_activeTab);

  Future<void> _goHomeForTab(_BrowserTab tab) async {
    if (!_tabs.contains(tab)) return;
    try {
      await tab.controller?.stopLoading();
      await tab.controller?.loadUrl(
        urlRequest: URLRequest(url: WebUri('about:blank')),
      );
    } catch (_) {
      // The widget is also removed below, so an unavailable native view is harmless.
    }
    if (!mounted || !_tabs.contains(tab)) return;
    setState(() {
      tab.controller = null;
      tab.initialUrl = null;
      tab.currentUrl = null;
      tab.title = 'زبانهٔ جدید';
      tab.rendererGone = false;
      tab.rendererDidCrash = false;
      tab.webviewRevision++;
      tab.isLoading = false;
      tab.progress = 0;
      tab.canGoBack = false;
      tab.canGoForward = false;
      if (identical(tab, _activeTab)) {
        _addressController.clear();
        _error = null;
        _isBookmarked = false;
      }
    });
  }

  void _retryRendererTab(_BrowserTab tab) {
    if (!_tabs.contains(tab) || tab.currentUrl == null) return;
    setState(() {
      tab.rendererGone = false;
      tab.rendererDidCrash = false;
      tab.initialUrl = tab.currentUrl;
      tab.controller = null;
      tab.webviewRevision++;
      tab.isLoading = true;
      tab.progress = 0;
      tab.canGoBack = false;
      tab.canGoForward = false;
      if (identical(tab, _activeTab)) _error = null;
    });
  }

  void _createTab() {
    if (_tabs.length >= _maxTabs) {
      setState(
        () => _error = orbitTextPair(
          context,
          'حداکثر $_maxTabs زبانه می‌توانی باز داشته باشی.',
          'You can have at most $_maxTabs tabs open.',
        ),
      );
      return;
    }
    setState(() {
      _tabs.add(_BrowserTab(_nextTabId++));
      _activeTabIndex = _tabs.length - 1;
      _addressController.clear();
      _isBookmarked = false;
      _error = null;
    });
  }

  void _activateTab(int index) {
    if (index < 0 || index >= _tabs.length) return;
    setState(() {
      _activeTabIndex = index;
      _addressController.text = _activeTab.currentUrl ?? '';
      _isBookmarked = false;
      _error = null;
    });
    unawaited(_refreshBookmarkStatus());
  }

  void _closeTab(int index) {
    if (_tabs.length == 1) {
      _activateTab(index);
      unawaited(_goHome());
      return;
    }
    setState(() {
      _tabs.removeAt(index);
      if (_activeTabIndex > index) _activeTabIndex--;
      if (_activeTabIndex >= _tabs.length) _activeTabIndex = _tabs.length - 1;
      _addressController.text = _activeTab.currentUrl ?? '';
      _isBookmarked = false;
    });
    unawaited(_refreshBookmarkStatus());
  }

  Future<void> _showTabSwitcher() async {
    final selectedId = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              child: Text(
                orbitText(context, 'زبانه‌های باز'),
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                orbitText(
                  context,
                  'زبانه‌های زنده می‌توانند از حافظهٔ دستگاه استفاده کنند. Orbit زبانه‌ها را خودکار حذف نمی‌کند تا تاریخچهٔ هرکدام حفظ شود.',
                ),
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: const Color(0xFF9AA5B5)),
              ),
            ),
            for (var i = 0; i < _tabs.length; i++)
              Card(
                color: i == _activeTabIndex
                    ? const Color(0xFF182839)
                    : const Color(0xFF111722),
                child: ListTile(
                  leading: Icon(
                    i == _activeTabIndex
                        ? Icons.radio_button_checked
                        : Icons.language,
                    color: i == _activeTabIndex ? _accent : null,
                  ),
                  title: Text(
                    orbitText(context, _tabs[i].title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    _tabs[i].currentUrl ?? orbitText(context, 'زبانهٔ خالی'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.pop(context, _tabs[i].id),
                  trailing: IconButton(
                    tooltip: orbitText(context, 'بستن زبانه'),
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      final id = _tabs[i].id;
                      Navigator.pop(context);
                      _closeTab(_tabs.indexWhere((tab) => tab.id == id));
                    },
                  ),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: Text(orbitText(context, 'زبانهٔ جدید')),
              onTap: () {
                Navigator.pop(context, -1);
              },
            ),
          ],
        ),
      ),
    );
    if (!mounted || selectedId == null) return;
    if (selectedId == -1) {
      _createTab();
    } else {
      final index = _tabs.indexWhere((tab) => tab.id == selectedId);
      _activateTab(index);
    }
  }

  Future<void> _openLibrary() async {
    final url = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => BrowserLibraryScreen(
          store: _store,
          onToggleLocale: widget.onToggleLocale,
        ),
      ),
    );
    if (url != null && mounted) await _openAddress(url);
  }

  Future<void> _openSecurityGuide() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            SecurityGuideScreen(onToggleLocale: widget.onToggleLocale),
      ),
    );
  }

  Future<void> _findOnPage(String value) async {
    if (value.trim().isEmpty) return;
    await _activeTab.controller?.findAllAsync(find: value.trim());
  }

  Future<void> _clearSiteData() async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(orbitText(context, 'پاک‌کردن داده‌های سایت؟')),
            content: Text(
              orbitText(
                context,
                'کوکی‌ها، cache و داده‌های وب ذخیره‌شده پاک می‌شوند و ممکن است از سایت‌ها خارج شوی. '
                'تاریخچه و نشانک‌ها جداگانه در کتابخانه مدیریت می‌شوند.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(orbitText(context, 'انصراف')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(orbitText(context, 'پاک‌کردن دادهٔ سایت')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await CookieManager.instance().deleteAllCookies();
      await WebStorageManager.instance().deleteAllData();
      for (final tab in _tabs) {
        final controller = tab.controller;
        if (controller == null) continue;
        await controller.clearCache();
        await controller.webStorage.localStorage.clear();
        await controller.webStorage.sessionStorage.clear();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(orbitText(context, 'داده‌های وب پاک شدند.'))),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              orbitText(
                context,
                'پاک‌سازی کامل نشد؛ بخشی از داده‌ها ممکن است باقی مانده باشد.',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _onDownloadStart(DownloadStartRequest request) async {
    final url = request.url.toString();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(orbitText(context, 'درخواست دریافت فایل')),
        content: Text(
          orbitTextPair(
            context,
            'این صفحه درخواست دانلود داده است. لینک را می‌توانی کپی کنی و در دانلودمنیجر دستگاه باز کنی.\n\n${request.suggestedFilename ?? url}',
            'This page requested a download. You can copy the link and open it in your device’s download manager.\n\n${request.suggestedFilename ?? url}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(orbitText(context, 'بستن')),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (context.mounted) Navigator.pop(context);
              if (mounted)
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text(
                      orbitText(this.context, 'نشانی دانلود کپی شد.'),
                    ),
                  ),
                );
            },
            icon: const Icon(Icons.copy),
            label: Text(orbitText(context, 'کپی لینک')),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _addressController.dispose();
    _findController.dispose();
    _vpnSubscription?.cancel();
    for (final tab in _tabs) {
      unawaited(tab.controller?.stopLoading() ?? Future<void>.value());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUri = Uri.tryParse(_activeTab.currentUrl ?? '');
    final https = currentUri?.scheme.toLowerCase() == 'https';
    final children = _tabs.map(_buildTabView).toList(growable: false);
    final vpnSubtitle = _vpnState == 'connected'
        ? (_timezoneBusy
              ? orbitText(context, 'VPN متصل · در حال بررسی timezone')
              : orbitTextPair(
                  context,
                  'VPN متصل · ${_timezone ?? 'timezone دستگاه'}',
                  'VPN connected · ${_timezone ?? 'device time zone'}',
                ))
        : orbitText(context, 'برای وب‌گردی VPN را وصل کن');

    return PopScope<Object?>(
      canPop: _canExitFromCurrentTab,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _handlingSystemBack) return;
        unawaited(_handleSystemBack());
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 12,
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF52E6DF), Color(0xFF4D83F6)],
                  ),
                ),
                child: const Icon(
                  Icons.travel_explore_rounded,
                  color: Color(0xFF07121A),
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Orbit Browser',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    Text(
                      vpnSubtitle,
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: const Color(0xFF9AA5B5)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: orbitText(context, 'تغییر زبان'),
              onPressed: widget.onToggleLocale,
              icon: Text(
                Localizations.localeOf(context).languageCode == 'en'
                    ? 'FA'
                    : 'EN',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              tooltip: orbitText(
                context,
                _isBookmarked ? 'حذف نشانک' : 'افزودن نشانک',
              ),
              onPressed: _activeTab.currentUrl == null ? null : _toggleBookmark,
              icon: Icon(
                _isBookmarked ? Icons.bookmark : Icons.bookmark_add_outlined,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: orbitText(context, 'ابزارهای مرورگر'),
              onSelected: (value) {
                if (value == 'library') unawaited(_openLibrary());
                if (value == 'security') unawaited(_openSecurityGuide());
                if (value == 'clear') unawaited(_clearSiteData());
                if (value == 'find')
                  setState(() => _showFindBar = !_showFindBar);
                if (value == 'timezone') unawaited(_editTimezonePreference());
                if (value == 'cookies') unawaited(_toggleThirdPartyCookies());
                if (value == 'vpn') widget.onOpenVpn?.call(context);
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'library',
                  child: ListTile(
                    leading: const Icon(Icons.bookmarks_outlined),
                    title: Text(orbitText(context, 'تاریخچه و نشانک‌ها')),
                  ),
                ),
                PopupMenuItem(
                  value: 'find',
                  child: ListTile(
                    leading: const Icon(Icons.search),
                    title: Text(orbitText(context, 'پیداکردن در صفحه')),
                  ),
                ),
                PopupMenuItem(
                  value: 'cookies',
                  child: ListTile(
                    leading: const Icon(Icons.cookie),
                    title: Text(
                      orbitText(
                        context,
                        _thirdPartyCookiesEnabled
                            ? 'مسدودکردن کوکی شخص ثالث'
                            : 'اجازهٔ کوکی شخص ثالث',
                      ),
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: 'timezone',
                  child: ListTile(
                    leading: const Icon(Icons.schedule_outlined),
                    title: Text(
                      orbitText(
                        context,
                        _timezoneLookupEnabled
                            ? 'تنظیم timezone مرورگر'
                            : 'فعال‌کردن timezone VPN',
                      ),
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: 'clear',
                  child: ListTile(
                    leading: const Icon(Icons.cleaning_services_outlined),
                    title: Text(orbitText(context, 'پاک‌کردن داده‌های سایت')),
                  ),
                ),
                PopupMenuItem(
                  value: 'security',
                  child: ListTile(
                    leading: const Icon(Icons.security_outlined),
                    title: Text(orbitText(context, 'امنیت و حریم خصوصی')),
                  ),
                ),
                PopupMenuItem(
                  value: 'vpn',
                  child: ListTile(
                    leading: const Icon(Icons.shield_outlined),
                    title: Text(orbitText(context, 'اتصال VPN')),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
              child: TextField(
                controller: _addressController,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) => _openAddress(),
                decoration: InputDecoration(
                  hintText: orbitText(context, 'نشانی وب یا جست‌وجو'),
                  prefixIcon: Icon(
                    https ? Icons.lock_outline : Icons.public,
                    color: https
                        ? const Color(0xFF47D7A0)
                        : const Color(0xFFFFC46B),
                  ),
                  suffixIcon: IconButton(
                    tooltip: orbitText(context, 'رفتن'),
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: _ready ? _openAddress : null,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF111722),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            if (_showFindBar)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _findController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: _findOnPage,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: orbitText(context, 'عبارت در این صفحه'),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: orbitText(context, 'نتیجهٔ قبلی'),
                      onPressed: () =>
                          _activeTab.controller?.findNext(forward: false),
                      icon: const Icon(Icons.keyboard_arrow_up),
                    ),
                    IconButton(
                      tooltip: orbitText(context, 'نتیجهٔ بعدی'),
                      onPressed: () =>
                          _activeTab.controller?.findNext(forward: true),
                      icon: const Icon(Icons.keyboard_arrow_down),
                    ),
                    IconButton(
                      tooltip: orbitText(context, 'بستن جست‌وجو'),
                      onPressed: () => setState(() => _showFindBar = false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            if (_activeTab.isLoading)
              LinearProgressIndicator(
                value: _activeTab.progress == 0 || _activeTab.progress >= 100
                    ? null
                    : _activeTab.progress / 100,
                minHeight: 2,
              ),
            Expanded(
              child: IndexedStack(index: _activeTabIndex, children: children),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                child: Text(
                  orbitText(context, _error!),
                  style: const TextStyle(
                    color: Color(0xFFFF7B84),
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(10, 2, 10, 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF111722),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFF293342)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x44000000),
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: orbitText(context, 'بازگشت'),
                  onPressed: _activeTab.canGoBack ? _goBack : null,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                IconButton(
                  tooltip: orbitText(context, 'جلو'),
                  onPressed: _activeTab.canGoForward ? _goForward : null,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
                IconButton(
                  tooltip: orbitText(context, 'خانه'),
                  onPressed: _goHome,
                  icon: const Icon(Icons.home_rounded),
                ),
                IconButton(
                  tooltip: orbitText(
                    context,
                    _activeTab.isLoading ? 'توقف بارگذاری' : 'بارگذاری دوباره',
                  ),
                  onPressed: _activeTab.controller == null
                      ? null
                      : _activeTab.isLoading
                      ? () => _activeTab.controller?.stopLoading()
                      : () => _activeTab.controller?.reload(),
                  icon: Icon(
                    _activeTab.isLoading
                        ? Icons.close_rounded
                        : Icons.refresh_rounded,
                  ),
                ),
                IconButton(
                  tooltip: orbitText(context, 'زبانهٔ جدید'),
                  onPressed: _createTab,
                  icon: const Icon(Icons.add_rounded),
                ),
                TextButton.icon(
                  onPressed: _showTabSwitcher,
                  icon: const Icon(Icons.tab_rounded, size: 19),
                  label: Text('${_activeTabIndex + 1}/${_tabs.length}'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabView(_BrowserTab tab) {
    if (tab.rendererGone) {
      return _RendererRecoveryCard(
        key: ValueKey('renderer-gone-${tab.id}-${tab.webviewRevision}'),
        crashed: tab.rendererDidCrash,
        url: tab.currentUrl,
        onRetry: () => _retryRendererTab(tab),
        onHome: () => _goHomeForTab(tab),
      );
    }
    final initialUrl = tab.initialUrl;
    if (initialUrl == null) {
      return _BrowserHome(
        key: ValueKey('home-${tab.id}'),
        connected: _vpnState == 'connected',
        timezone: _timezone,
        timezoneBusy: _timezoneBusy,
        timezoneError: _timezoneError,
        onSearch: (query) => _openAddressInTab(tab, query),
        onLibrary: _openLibrary,
        onSecurity: _openSecurityGuide,
        onOpenVpn: () => widget.onOpenVpn?.call(context),
      );
    }

    final scripts = _timezone == null
        ? null
        : UnmodifiableListView<UserScript>([
            UserScript(
              groupName: 'orbit-vpn-timezone',
              source: _timezoneService.buildDocumentStartScript(_timezone!),
              injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              forMainFrameOnly: true,
            ),
          ]);

    return InAppWebView(
      key: ValueKey('web-${tab.id}-${tab.webviewRevision}'),
      initialUrlRequest: URLRequest(url: WebUri(initialUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        javaScriptCanOpenWindowsAutomatically: false,
        domStorageEnabled: true,
        databaseEnabled: true,
        safeBrowsingEnabled: true,
        allowFileAccess: false,
        allowContentAccess: false,
        geolocationEnabled: false,
        thirdPartyCookiesEnabled: _thirdPartyCookiesEnabled,
        useWideViewPort: true,
        loadWithOverviewMode: true,
        supportZoom: true,
        builtInZoomControls: true,
        displayZoomControls: false,
        supportMultipleWindows: false,
        mediaPlaybackRequiresUserGesture: true,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_NEVER_ALLOW,
        useShouldOverrideUrlLoading: true,
        useOnDownloadStart: true,
        isInspectable: false,
        useOnRenderProcessGone: true,
      ),
      initialUserScripts: scripts,
      onWebViewCreated: (controller) {
        if (!mounted || !_tabs.contains(tab)) return;
        tab.controller = controller;
        if (mounted) setState(() {});
      },
      onProgressChanged: (controller, progress) {
        if (!mounted ||
            !_tabs.contains(tab) ||
            !identical(tab.controller, controller))
          return;
        setState(() {
          tab.progress = progress;
          tab.isLoading = progress < 100;
        });
      },
      onLoadStart: (controller, url) {
        if (!mounted ||
            !_tabs.contains(tab) ||
            !identical(tab.controller, controller))
          return;
        setState(() {
          tab.isLoading = true;
          tab.progress = 0;
          if (url != null && url.toString() != 'about:blank') {
            tab.currentUrl = url.toString();
            if (identical(tab, _activeTab))
              _addressController.text = url.toString();
          }
        });
      },
      onLoadStop: (controller, url) => _onPageFinished(tab, controller, url),
      onUpdateVisitedHistory: (controller, url, isReload) {
        if (!mounted ||
            !_tabs.contains(tab) ||
            !identical(tab.controller, controller))
          return;
        unawaited(_refreshTabNavigation(tab, controller));
      },
      onTitleChanged: (controller, title) {
        if (!mounted ||
            !_tabs.contains(tab) ||
            !identical(tab.controller, controller) ||
            title == null ||
            title.isEmpty)
          return;
        setState(() => tab.title = title);
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame != true ||
            !mounted ||
            !_tabs.contains(tab) ||
            !identical(tab.controller, controller))
          return;
        setState(() {
          tab.isLoading = false;
          _error = 'بارگذاری صفحه ناموفق بود. اتصال یا نشانی را بررسی کن.';
        });
      },
      onRenderProcessGone: (controller, detail) {
        if (!mounted ||
            !_tabs.contains(tab) ||
            !identical(tab.controller, controller))
          return;
        setState(() {
          tab.controller = null;
          tab.initialUrl = null;
          tab.rendererGone = true;
          tab.rendererDidCrash = detail.didCrash;
          tab.isLoading = false;
          tab.progress = 0;
          tab.canGoBack = false;
          tab.canGoForward = false;
          _error = detail.didCrash
              ? 'موتور صفحه از کار افتاد؛ می‌توانی همین تب را دوباره بارگذاری کنی.'
              : 'Android موتور این صفحه را متوقف کرد؛ می‌توانی دوباره تلاش کنی.';
        });
      },
      shouldOverrideUrlLoading: (_, action) async {
        final url = action.request.url?.toString();
        if (url == 'about:blank') return NavigationActionPolicy.ALLOW;
        if (_vpnState != 'connected' || url == null)
          return NavigationActionPolicy.CANCEL;
        final uri = Uri.tryParse(url);
        if (uri == null ||
            !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
          return NavigationActionPolicy.CANCEL;
        }
        return NavigationActionPolicy.ALLOW;
      },
      onPermissionRequest: (_, __) async =>
          PermissionResponse(action: PermissionResponseAction.DENY),
      onGeolocationPermissionsShowPrompt: (_, origin) async =>
          GeolocationPermissionShowPromptResponse(
            origin: origin,
            allow: false,
            retain: false,
          ),
      onDownloadStartRequest: (_, request) => _onDownloadStart(request),
    );
  }
}

class _BrowserTab {
  _BrowserTab(this.id);

  final int id;
  int webviewRevision = 0;
  String? initialUrl;
  String? currentUrl;
  String title = 'زبانهٔ جدید';
  InAppWebViewController? controller;
  bool isLoading = false;
  int progress = 0;
  bool canGoBack = false;
  bool canGoForward = false;
  bool rendererGone = false;
  bool rendererDidCrash = false;
}

class _RendererRecoveryCard extends StatelessWidget {
  const _RendererRecoveryCard({
    super.key,
    required this.crashed,
    required this.url,
    required this.onRetry,
    required this.onHome,
  });

  final bool crashed;
  final String? url;
  final VoidCallback onRetry;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          color: const Color(0xFF151B28),
          border: Border.all(color: const Color(0x55FFC46B)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.memory_rounded,
              color: Color(0xFFFFC46B),
              size: 48,
            ),
            const SizedBox(height: 14),
            Text(
              orbitText(
                context,
                crashed
                    ? 'موتور صفحه از کار افتاد؛ می‌توانی همین تب را دوباره بارگذاری کنی.'
                    : 'Android موتور این صفحه را متوقف کرد؛ می‌توانی دوباره تلاش کنی.',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              orbitText(
                context,
                'این تب پس از توقف موتور صفحه قابل بازیابی است؛ تلاش دوباره صفحهٔ فعلی را بارگذاری می‌کند. تاریخچهٔ همین صفحه ممکن است در دسترس نباشد.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFADB7C8), height: 1.6),
            ),
            if (url != null) ...[
              const SizedBox(height: 12),
              Text(
                url!,
                textDirection: TextDirection.ltr,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF52E6DF), fontSize: 12),
              ),
            ],
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(orbitText(context, 'تلاش دوباره')),
                ),
                OutlinedButton.icon(
                  onPressed: onHome,
                  icon: const Icon(Icons.home_outlined),
                  label: Text(orbitText(context, 'بازگشت به خانه')),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _BrowserHome extends StatefulWidget {
  const _BrowserHome({
    super.key,
    required this.connected,
    required this.timezone,
    required this.timezoneBusy,
    required this.timezoneError,
    required this.onSearch,
    required this.onLibrary,
    required this.onSecurity,
    required this.onOpenVpn,
  });

  final bool connected;
  final String? timezone;
  final bool timezoneBusy;
  final String? timezoneError;
  final ValueChanged<String> onSearch;
  final VoidCallback onLibrary;
  final VoidCallback onSecurity;
  final VoidCallback onOpenVpn;

  @override
  State<_BrowserHome> createState() => _BrowserHomeState();
}

class _BrowserHomeState extends State<_BrowserHome> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF13313B),
                    Color(0xFF192235),
                    Color(0xFF111620),
                  ],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                border: Border.all(color: const Color(0x5552E6DF)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x2252E6DF),
                    blurRadius: 34,
                    offset: Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0x2252E6DF),
                      border: Border.all(
                        color: const Color(0x6652E6DF),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.travel_explore_rounded,
                      color: _BrowserScreenState._accent,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    orbitText(context, 'جست‌وجو یا نشانی را وارد کن'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    orbitText(
                      context,
                      widget.connected
                          ? 'JavaScript و ذخیره‌سازی وب فعال است. تاریخچه و نشانک‌ها روی همین دستگاه می‌مانند.'
                          : 'برای جلوگیری از شروع ناخواستهٔ بارگذاری، تا اتصال VPN هیچ سایتی باز نمی‌شود.',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFB9C6D4),
                      height: 1.65,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _searchController,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.search,
                    onSubmitted: widget.onSearch,
                    decoration: InputDecoration(
                      hintText: orbitText(context, 'جست‌وجو در وب'),
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: IconButton(
                        tooltip: orbitText(context, 'جست‌وجو'),
                        icon: const Icon(Icons.arrow_forward_rounded),
                        onPressed: () =>
                            widget.onSearch(_searchController.text),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF0E141E),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (widget.connected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x2247D7A0),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.shield_rounded,
                            color: Color(0xFF47D7A0),
                            size: 17,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            orbitText(context, 'VPN متصل'),
                            style: const TextStyle(
                              color: Color(0xFF8FE8C4),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    FilledButton.icon(
                      onPressed: widget.onOpenVpn,
                      icon: const Icon(Icons.shield_outlined),
                      label: Text(orbitText(context, 'بازکردن اتصال VPN')),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (widget.connected) ...[
              if (widget.timezoneBusy)
                Text(
                  orbitText(
                    context,
                    'در حال دریافت منطقهٔ زمانی از IP خروجی VPN…',
                  ),
                  style: const TextStyle(color: Color(0xFF99A4B5)),
                ),
              if (widget.timezone != null)
                Text(
                  orbitTextPair(
                    context,
                    'منطقهٔ زمانی مرورگر: ${widget.timezone} · best-effort',
                    'Browser time zone: ${widget.timezone} · best effort',
                  ),
                  style: const TextStyle(color: _BrowserScreenState._accent),
                ),
              if (widget.timezoneError != null)
                Text(
                  orbitText(context, widget.timezoneError!),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFFFC46B)),
                ),
            ],
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                OutlinedButton.icon(
                  onPressed: widget.onLibrary,
                  icon: const Icon(Icons.bookmarks_outlined),
                  label: Text(orbitText(context, 'کتابخانه')),
                ),
                OutlinedButton.icon(
                  onPressed: widget.onSecurity,
                  icon: const Icon(Icons.security_outlined),
                  label: Text(orbitText(context, 'امنیت و حریم خصوصی')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              orbitText(
                context,
                'برای قفل‌کردن کل دستگاه، Always-on VPN و Block connections without VPN را در تنظیمات Android هم فعال کن.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF788397),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
