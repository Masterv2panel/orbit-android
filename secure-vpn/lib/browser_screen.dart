// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'browser_library_screen.dart';
import 'browser_store.dart';
import 'security_guide_screen.dart';
import 'vpn_service.dart';
import 'vpn_timezone_service.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key, this.onOpenVpn});

  final ValueChanged<BuildContext>? onOpenVpn;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  static const _maxTabs = 12;
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
  int _webviewRevision = 0;
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

  _BrowserTab get _activeTab => _tabs[_activeTabIndex];

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
      enabled = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('هماهنگ‌سازی timezone مرورگر؟'),
              content: const Text(
                'برای برآورد منطقهٔ زمانی، Orbit یک درخواست HTTPS به ipapi.co می‌فرستد. این سرویس IP خروجی VPN را دریافت می‌کند. '
                'تنظیم فقط روی JavaScript مرورگر اثر می‌گذارد، نه ساعت Android، و ممکن است در WebViewهای قدیمی دیر اعمال شود.',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('فعلاً نه')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('فعال‌سازی')),
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
      setState(() => _timezoneError = 'درخواست بیرونی timezone غیرفعال است؛ از timezone دستگاه استفاده می‌شود.');
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
    if (_vpnState != 'connected' || _timezone != null || _timezoneError != null) return;
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
            title: const Text('منطقهٔ زمانی خروجی VPN'),
            content: const Text(
              'هنگام فعال‌بودن، ipapi.co درخواست دریافت می‌کند و IP خروجی VPN را می‌بیند. '
              'در صورت خاموش‌کردن، صفحات جدید از timezone دستگاه استفاده می‌کنند.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('خاموش و استفاده از دستگاه')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('فعال‌سازی / تلاش دوباره')),
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
      if (tab.currentUrl == null) continue;
      try {
        await tab.controller?.stopLoading();
      } catch (_) {
        // A WebView may already be disposing.
      }
      tab.initialUrl = tab.currentUrl;
      tab.controller = null;
      tab.isLoading = true;
      tab.progress = 0;
    }
    if (!mounted) return;
    setState(() => _webviewRevision++);
  }

  Future<void> _toggleThirdPartyCookies() async {
    final enable = !_thirdPartyCookiesEnabled;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(enable ? 'فعال‌کردن کوکی شخص ثالث؟' : 'مسدودکردن کوکی شخص ثالث؟'),
            content: Text(enable
                ? 'این کار ممکن است ورود یا پرداخت بعضی سایت‌ها را بهتر کند، اما سرویس‌های تعبیه‌شده می‌توانند کوکی بین‌سایتی داشته باشند.'
                : 'با مسدودکردن، حریم خصوصی بهتر می‌شود؛ ورود یکپارچه یا برخی امکانات سایت ممکن است از کار بیفتد.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('تأیید')),
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
          await controller.loadUrl(urlRequest: URLRequest(url: WebUri('about:blank')));
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
    if (uri == null || uri.host.isEmpty || !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      return null;
    }
    return uri;
  }

  Future<void> _openAddress([String? raw]) => _openAddressInTab(_activeTab, raw ?? _addressController.text);

  Future<void> _openAddressInTab(_BrowserTab tab, String input) async {
    if (_vpnState != 'connected') {
      if (mounted) setState(() => _error = 'قفل مرورگر فعال است؛ برای وب‌گردی ابتدا VPN را وصل کن.');
      return;
    }
    final uri = _destinationFor(input);
    if (uri == null) {
      if (mounted) setState(() => _error = 'نشانی معتبر HTTP/HTTPS یا عبارت جست‌وجو وارد کن.');
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
        await controller.loadUrl(urlRequest: URLRequest(url: WebUri(uri.toString())));
      }
    } catch (_) {
      if (mounted) setState(() {
        tab.isLoading = false;
        _error = 'بارگذاری شروع نشد. نشانی یا اتصال VPN را بررسی کن.';
      });
    }
  }

  Future<void> _onPageFinished(_BrowserTab tab, InAppWebViewController controller, WebUri? reportedUrl) async {
    if (!mounted || _vpnState != 'connected' || !_tabs.contains(tab)) return;
    final webUrl = await controller.getUrl();
    final currentUrl = webUrl?.toString() ?? reportedUrl?.toString();
    final title = (await controller.getTitle())?.trim();
    if (currentUrl == null || currentUrl == 'about:blank') {
      setState(() {
        tab.isLoading = false;
        tab.progress = 100;
      });
      return;
    }
    final parsed = Uri.tryParse(currentUrl);
    final safeTitle = (title == null || title.isEmpty) ? (parsed?.host ?? currentUrl) : title;
    tab.currentUrl = currentUrl;
    tab.title = safeTitle;
    tab.isLoading = false;
    tab.progress = 100;
    await _store.recordVisit(url: currentUrl, title: safeTitle);
    await _refreshTabNavigation(tab, controller);
    if (!mounted) return;
    setState(() {
      if (identical(tab, _activeTab)) _addressController.text = currentUrl;
    });
    if (identical(tab, _activeTab)) unawaited(_refreshBookmarkStatus());
  }

  Future<void> _refreshTabNavigation(_BrowserTab tab, InAppWebViewController controller) async {
    try {
      final canGoBack = await controller.canGoBack();
      final canGoForward = await controller.canGoForward();
      if (!mounted || !_tabs.contains(tab)) return;
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
    final saved = await _store.toggleBookmark(url: url, title: _activeTab.title);
    if (mounted) setState(() => _isBookmarked = saved);
  }

  Future<void> _goBack() async {
    final controller = _activeTab.controller;
    if (controller != null && await controller.canGoBack()) await controller.goBack();
  }

  Future<void> _goForward() async {
    final controller = _activeTab.controller;
    if (controller != null && await controller.canGoForward()) await controller.goForward();
  }

  Future<void> _goHome() async {
    final tab = _activeTab;
    try {
      await tab.controller?.stopLoading();
      await tab.controller?.loadUrl(urlRequest: URLRequest(url: WebUri('about:blank')));
    } catch (_) {
      // The widget is also removed below, so an unavailable native view is harmless.
    }
    setState(() {
      tab.controller = null;
      tab.initialUrl = null;
      tab.currentUrl = null;
      tab.title = 'زبانهٔ جدید';
      tab.isLoading = false;
      tab.progress = 0;
      tab.canGoBack = false;
      tab.canGoForward = false;
      _addressController.clear();
      _error = null;
      _isBookmarked = false;
    });
  }

  void _createTab() {
    if (_tabs.length >= _maxTabs) {
      setState(() => _error = 'حداکثر $_maxTabs زبانه می‌توانی باز داشته باشی.');
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
          children: [
            for (var i = 0; i < _tabs.length; i++)
              ListTile(
                leading: Icon(i == _activeTabIndex ? Icons.radio_button_checked : Icons.language),
                title: Text(_tabs[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(_tabs[i].currentUrl ?? 'زبانهٔ خالی'),
                onTap: () => Navigator.pop(context, _tabs[i].id),
                trailing: IconButton(
                  tooltip: 'بستن زبانه',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    final id = _tabs[i].id;
                    Navigator.pop(context);
                    _closeTab(_tabs.indexWhere((tab) => tab.id == id));
                  },
                ),
              ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('زبانهٔ جدید'),
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
      MaterialPageRoute<String>(builder: (_) => BrowserLibraryScreen(store: _store)),
    );
    if (url != null && mounted) await _openAddress(url);
  }

  Future<void> _openSecurityGuide() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const SecurityGuideScreen()),
    );
  }

  Future<void> _findOnPage(String value) async {
    if (value.trim().isEmpty) return;
    await _activeTab.controller?.findAllAsync(find: value.trim());
  }

  Future<void> _clearSiteData() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('پاک‌کردن داده‌های سایت؟'),
            content: const Text(
              'کوکی‌ها، cache و داده‌های وب ذخیره‌شده پاک می‌شوند و ممکن است از سایت‌ها خارج شوی. '
              'تاریخچه و نشانک‌ها جداگانه در کتابخانه مدیریت می‌شوند.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('پاک‌کردن دادهٔ سایت')),
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('داده‌های وب پاک شدند.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('پاک‌سازی کامل نشد؛ بخشی از داده‌ها ممکن است باقی مانده باشد.')));
      }
    }
  }

  Future<void> _onDownloadStart(DownloadStartRequest request) async {
    final url = request.url.toString();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('درخواست دریافت فایل'),
        content: Text(
          'این صفحه درخواست دانلود داده است. لینک را می‌توانی کپی کنی و در دانلودمنیجر دستگاه باز کنی.\n\n${request.suggestedFilename ?? url}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('بستن')),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (context.mounted) Navigator.pop(context);
              if (mounted) ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(content: Text('نشانی دانلود کپی شد.')));
            },
            icon: const Icon(Icons.copy),
            label: const Text('کپی لینک'),
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

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Orbit Browser', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            Text(
              _vpnState == 'connected'
                  ? (_timezoneBusy ? 'VPN متصل · در حال بررسی timezone' : 'VPN متصل · ${_timezone ?? 'timezone دستگاه'}')
                  : 'برای وب‌گردی VPN را وصل کن',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF9AA5B5)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _isBookmarked ? 'حذف نشانک' : 'افزودن نشانک',
            onPressed: _activeTab.currentUrl == null ? null : _toggleBookmark,
            icon: Icon(_isBookmarked ? Icons.bookmark : Icons.bookmark_add_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'ابزارهای مرورگر',
            onSelected: (value) {
              if (value == 'library') unawaited(_openLibrary());
              if (value == 'security') unawaited(_openSecurityGuide());
              if (value == 'clear') unawaited(_clearSiteData());
              if (value == 'find') setState(() => _showFindBar = !_showFindBar);
              if (value == 'timezone') unawaited(_editTimezonePreference());
              if (value == 'cookies') unawaited(_toggleThirdPartyCookies());
              if (value == 'vpn') widget.onOpenVpn?.call(context);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'library', child: ListTile(leading: Icon(Icons.bookmarks_outlined), title: Text('تاریخچه و نشانک‌ها'))),
              const PopupMenuItem(value: 'find', child: ListTile(leading: Icon(Icons.search), title: Text('پیداکردن در صفحه'))),
              PopupMenuItem(value: 'cookies', child: ListTile(leading: Icon(Icons.cookie), title: Text(_thirdPartyCookiesEnabled ? 'مسدودکردن کوکی شخص ثالث' : 'اجازهٔ کوکی شخص ثالث'))),
              PopupMenuItem(value: 'timezone', child: ListTile(leading: Icon(Icons.schedule_outlined), title: Text(_timezoneLookupEnabled ? 'تنظیم timezone مرورگر' : 'فعال‌کردن timezone VPN'))),
              const PopupMenuItem(value: 'clear', child: ListTile(leading: Icon(Icons.cleaning_services_outlined), title: Text('پاک‌کردن داده‌های سایت'))),
              const PopupMenuItem(value: 'security', child: ListTile(leading: Icon(Icons.security_outlined), title: Text('امنیت و حریم خصوصی'))),
              const PopupMenuItem(value: 'vpn', child: ListTile(leading: Icon(Icons.shield_outlined), title: Text('اتصال VPN'))),
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
                hintText: 'نشانی وب یا جست‌وجو',
                prefixIcon: Icon(https ? Icons.lock_outline : Icons.public,
                    color: https ? const Color(0xFF47D7A0) : const Color(0xFFFFC46B)),
                suffixIcon: IconButton(
                  tooltip: 'رفتن',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _ready ? _openAddress : null,
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
                filled: true,
                fillColor: const Color(0xFF111722),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                      decoration: const InputDecoration(isDense: true, hintText: 'عبارت در این صفحه'),
                    ),
                  ),
                  IconButton(tooltip: 'نتیجهٔ قبلی', onPressed: () => _activeTab.controller?.findNext(forward: false), icon: const Icon(Icons.keyboard_arrow_up)),
                  IconButton(tooltip: 'نتیجهٔ بعدی', onPressed: () => _activeTab.controller?.findNext(forward: true), icon: const Icon(Icons.keyboard_arrow_down)),
                  IconButton(tooltip: 'بستن جست‌وجو', onPressed: () => setState(() => _showFindBar = false), icon: const Icon(Icons.close)),
                ],
              ),
            ),
          if (_activeTab.isLoading)
            LinearProgressIndicator(
              value: _activeTab.progress == 0 || _activeTab.progress >= 100 ? null : _activeTab.progress / 100,
              minHeight: 2,
            ),
          Expanded(child: IndexedStack(index: _activeTabIndex, children: children)),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
              child: Text(_error!, style: const TextStyle(color: Color(0xFFFF7B84), fontSize: 12)),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(tooltip: 'بازگشت', onPressed: _activeTab.canGoBack ? _goBack : null, icon: const Icon(Icons.arrow_back)),
              IconButton(tooltip: 'جلو', onPressed: _activeTab.canGoForward ? _goForward : null, icon: const Icon(Icons.arrow_forward)),
              IconButton(tooltip: 'خانه', onPressed: _goHome, icon: const Icon(Icons.home_outlined)),
              IconButton(
                tooltip: _activeTab.isLoading ? 'توقف بارگذاری' : 'بارگذاری دوباره',
                onPressed: _activeTab.controller == null
                    ? null
                    : _activeTab.isLoading
                        ? () => _activeTab.controller?.stopLoading()
                        : () => _activeTab.controller?.reload(),
                icon: Icon(_activeTab.isLoading ? Icons.close : Icons.refresh),
              ),
              IconButton(tooltip: 'زبانهٔ جدید', onPressed: _createTab, icon: const Icon(Icons.add)),
              TextButton.icon(
                onPressed: _showTabSwitcher,
                icon: const Icon(Icons.tab_outlined, size: 19),
                label: Text('${_activeTabIndex + 1}/${_tabs.length}'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabView(_BrowserTab tab) {
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
      key: ValueKey('web-${tab.id}-$_webviewRevision'),
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
      ),
      initialUserScripts: scripts,
      onWebViewCreated: (controller) {
        tab.controller = controller;
        if (mounted) setState(() {});
      },
      onProgressChanged: (_, progress) {
        if (!mounted || !_tabs.contains(tab)) return;
        setState(() {
          tab.progress = progress;
          tab.isLoading = progress < 100;
        });
      },
      onLoadStart: (_, url) {
        if (!mounted || !_tabs.contains(tab)) return;
        setState(() {
          tab.isLoading = true;
          tab.progress = 0;
          if (url != null && url.toString() != 'about:blank') {
            tab.currentUrl = url.toString();
            if (identical(tab, _activeTab)) _addressController.text = url.toString();
          }
        });
      },
      onLoadStop: (controller, url) => _onPageFinished(tab, controller, url),
      onTitleChanged: (_, title) {
        if (!mounted || !_tabs.contains(tab) || title == null || title.isEmpty) return;
        setState(() => tab.title = title);
      },
      onReceivedError: (_, request, error) {
        if (request.isForMainFrame != true || !mounted || !_tabs.contains(tab)) return;
        setState(() {
          tab.isLoading = false;
          _error = 'بارگذاری صفحه ناموفق بود. اتصال یا نشانی را بررسی کن.';
        });
      },
      shouldOverrideUrlLoading: (_, action) async {
        final url = action.request.url?.toString();
        if (url == 'about:blank') return NavigationActionPolicy.ALLOW;
        if (_vpnState != 'connected' || url == null) return NavigationActionPolicy.CANCEL;
        final uri = Uri.tryParse(url);
        if (uri == null || !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
          return NavigationActionPolicy.CANCEL;
        }
        return NavigationActionPolicy.ALLOW;
      },
      onPermissionRequest: (_, __) async => PermissionResponse(action: PermissionResponseAction.DENY),
      onGeolocationPermissionsShowPrompt: (_, origin) async =>
          GeolocationPermissionShowPromptResponse(origin: origin, allow: false, retain: false),
      onDownloadStartRequest: (_, request) => _onDownloadStart(request),
    );
  }
}

class _BrowserTab {
  _BrowserTab(this.id);

  final int id;
  String? initialUrl;
  String? currentUrl;
  String title = 'زبانهٔ جدید';
  InAppWebViewController? controller;
  bool isLoading = false;
  int progress = 0;
  bool canGoBack = false;
  bool canGoForward = false;
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
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  color: const Color(0xFF152532),
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: const Color(0x3352E6DF)),
                ),
                child: const Icon(Icons.travel_explore, color: _BrowserScreenState._accent, size: 42),
              ),
              const SizedBox(height: 18),
              Text('جست‌وجو یا نشانی را وارد کن', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                widget.connected
                    ? 'JavaScript و ذخیره‌سازی وب فعال است. تاریخچه و نشانک‌ها روی همین دستگاه می‌مانند.'
                    : 'برای جلوگیری از شروع ناخواستهٔ بارگذاری، تا اتصال VPN هیچ سایتی باز نمی‌شود.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF99A4B5), height: 1.65),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _searchController,
                textDirection: TextDirection.ltr,
                textInputAction: TextInputAction.search,
                onSubmitted: widget.onSearch,
                decoration: InputDecoration(
                  hintText: 'جست‌وجو در وب',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    tooltip: 'جست‌وجو',
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: () => widget.onSearch(_searchController.text),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 16),
              if (widget.connected) ...[
                if (widget.timezoneBusy)
                  const Text('در حال دریافت منطقهٔ زمانی از IP خروجی VPN…', style: TextStyle(color: Color(0xFF99A4B5))),
                if (widget.timezone != null)
                  Text('منطقهٔ زمانی مرورگر: ${widget.timezone} · best-effort', style: const TextStyle(color: _BrowserScreenState._accent)),
                if (widget.timezoneError != null)
                  Text(widget.timezoneError!, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFFC46B))),
              ] else
                FilledButton.icon(onPressed: widget.onOpenVpn, icon: const Icon(Icons.shield_outlined), label: const Text('بازکردن اتصال VPN')),
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(onPressed: widget.onLibrary, icon: const Icon(Icons.bookmarks_outlined), label: const Text('کتابخانه')),
                  OutlinedButton.icon(onPressed: widget.onSecurity, icon: const Icon(Icons.security_outlined), label: const Text('امنیت و حریم خصوصی')),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'برای قفل‌کردن کل دستگاه، Always-on VPN و Block connections without VPN را در تنظیمات Android هم فعال کن.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF788397), fontSize: 12, height: 1.5),
              ),
            ],
          ),
        ),
      );
}
