// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'vpn_service.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key, this.onOpenVpn});

  final ValueChanged<BuildContext>? onOpenVpn;

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final _addressController = TextEditingController();
  final _cookieManager = WebViewCookieManager();
  final _vpnService = OrbitVpnService.instance;
  late final _vpn = _vpnService.api;
  WebViewController? _webViewController;
  StreamSubscription<dynamic>? _vpnSubscription;
  String _vpnState = 'checking';
  bool _ready = false;
  bool _hasPage = false;
  bool _loading = false;
  bool _canGoBack = false;
  bool _canGoForward = false;
  int _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
    _initializeVpnStatus();
  }

  Future<void> _initializeVpnStatus() async {
    try {
      await _vpnService.initialize();
      _vpnSubscription = _vpn.status.listen((status) {
        _updateVpnState(status.state.toString().split('.').last);
      });
      final status = await _vpn.getStatus();
      _updateVpnState(status.state.toString().split('.').last);
    } catch (_) {
      _updateVpnState('disconnected');
    }
  }

  void _updateVpnState(String nextState) {
    final wasConnected = _vpnState == 'connected';
    if (mounted) setState(() => _vpnState = nextState);
    if (wasConnected && nextState != 'connected' && _hasPage) {
      unawaited(_failClosedAfterDisconnect());
    }
  }

  Future<void> _failClosedAfterDisconnect() async {
    try {
      await _webViewController?.loadRequest(Uri.parse('about:blank'));
      await _clearWebData();
    } catch (_) {
      // Android's system-level lockdown is required to cover every disconnect race.
    }
    if (!mounted) return;
    setState(() {
      _hasPage = false;
      _loading = false;
      _canGoBack = false;
      _canGoForward = false;
      _error = 'VPN قطع شد؛ صفحه برای جلوگیری از نشت پاک شد.';
    });
  }

  Future<void> _initializeWebView() async {
    final controller = WebViewController();
    _webViewController = controller;

    await controller.setBackgroundColor(const Color(0xFF080B12));
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
        onPageStarted: (url) {
          if (!mounted) return;
          setState(() {
            _loading = true;
            _error = null;
            _hasPage = url != 'about:blank';
            if (url != 'about:blank') _addressController.text = url;
          });
        },
        onPageFinished: (url) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _progress = 100;
            _hasPage = url != 'about:blank';
            if (url != 'about:blank') _addressController.text = url;
          });
          unawaited(_refreshPageState());
        },
        onWebResourceError: (error) {
          if (error.isForMainFrame != true || !mounted) return;
          setState(() {
            _loading = false;
            _error = 'بارگذاری صفحه ناموفق بود. اتصال یا نشانی را بررسی کن.';
          });
        },
        onNavigationRequest: (request) {
          if (request.url == 'about:blank') return NavigationDecision.navigate;
          if (_vpnState != 'connected') return NavigationDecision.prevent;
          final uri = Uri.tryParse(request.url);
          if (uri == null || !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ),
    );

    final platformController = controller.platform;
    if (platformController is AndroidWebViewController) {
      await platformController.setGeolocationEnabled(false);
      await platformController.setAllowFileAccess(false);
      await platformController.setAllowContentAccess(false);
      await platformController.setOnPlatformPermissionRequest((request) {
        unawaited(request.deny());
      });

      final cookiePlatform = _cookieManager.platform;
      if (cookiePlatform is AndroidWebViewCookieManager) {
        await cookiePlatform.setAcceptThirdPartyCookies(platformController, false);
      }
    }

    await _clearWebData(controller);
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _clearWebData([WebViewController? controller]) async {
    try {
      await _cookieManager.clearCookies();
      final webView = controller ?? _webViewController;
      if (webView != null) {
        await webView.clearCache();
        await webView.clearLocalStorage();
      }
    } catch (_) {
      // Clearing is best-effort; navigation remains available if a platform API fails.
    }
  }

  Uri? _destinationFor(String input) {
    final value = input.trim();
    if (value.isEmpty) return null;

    if (value.contains(RegExp(r'\s'))) {
      return Uri.https('html.duckduckgo.com', '/html/', {'q': value});
    }

    final candidate = value.contains('://') ? value : 'https://$value';
    final uri = Uri.tryParse(candidate);
    if (uri == null || uri.host.isEmpty || !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      return null;
    }
    return uri;
  }

  Future<void> _openAddress([String? raw]) async {
    if (_vpnState != 'connected') {
      setState(() => _error = 'قفل مرورگر فعال است؛ برای جلوگیری از نشت IP ابتدا VPN را وصل کن.');
      return;
    }
    final input = raw ?? _addressController.text;
    final uri = _destinationFor(input);
    if (uri == null) {
      setState(() => _error = 'نشانی معتبر HTTP/HTTPS یا عبارت جست‌وجو وارد کن.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _hasPage = true;
      _loading = true;
      _progress = 0;
      _addressController.text = uri.toString();
    });

    try {
      await _webViewController?.loadRequest(uri);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'بارگذاری شروع نشد. دوباره تلاش کن.';
        });
      }
    }
  }

  Future<void> _refreshPageState() async {
    final controller = _webViewController;
    if (controller == null) return;
    try {
      final canGoBack = await controller.canGoBack();
      final canGoForward = await controller.canGoForward();
      if (!mounted) return;
      setState(() {
        _canGoBack = canGoBack;
        _canGoForward = canGoForward;
      });
    } catch (_) {
      // The page may be changing while navigation state is read.
    }
  }

  Future<void> _goBack() async {
    final controller = _webViewController;
    if (controller != null && await controller.canGoBack()) await controller.goBack();
  }

  Future<void> _goForward() async {
    final controller = _webViewController;
    if (controller != null && await controller.canGoForward()) await controller.goForward();
  }

  Future<void> _goHome() async {
    await _clearWebData();
    _addressController.clear();
    await _webViewController?.loadRequest(Uri.parse('about:blank'));
    if (!mounted) return;
    setState(() {
      _hasPage = false;
      _loading = false;
      _error = null;
      _canGoBack = false;
      _canGoForward = false;
      _progress = 0;
    });
  }

  @override
  void dispose() {
    _addressController.dispose();
    _vpnSubscription?.cancel();
    unawaited(_clearWebData());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUri = Uri.tryParse(_addressController.text);
    final isHttps = currentUri?.scheme.toLowerCase() == 'https';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('مرورگر Orbit', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(
              _vpnState == 'connected'
                  ? 'VPN متصل · نشست خصوصی'
                  : 'قفل فعال · برای وب‌گردی VPN را وصل کن',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: const Color(0xFF8992A5)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'اتصال VPN',
            icon: const Icon(Icons.shield_outlined),
            onPressed: () => widget.onOpenVpn?.call(context),
          ),
          PopupMenuButton<String>(
            tooltip: 'گزینه‌های حریم خصوصی',
            onSelected: (value) {
              if (value == 'clear') _confirmClearData();
              if (value == 'privacy') _showPrivacyInfo();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'clear', child: Text('پاک‌کردن داده‌های نشست')),
              PopupMenuItem(value: 'privacy', child: Text('دربارهٔ حریم خصوصی')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: TextField(
              controller: _addressController,
              textDirection: TextDirection.ltr,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              autocorrect: false,
              enableSuggestions: false,
              onSubmitted: (_) => _openAddress(),
              decoration: InputDecoration(
                hintText: 'نشانی وب یا عبارت جست‌وجو',
                prefixIcon: Icon(isHttps ? Icons.lock_outline : Icons.public,
                    color: isHttps ? const Color(0xFF47D7A0) : const Color(0xFFFFC46B)),
                suffixIcon: IconButton(
                  tooltip: 'رفتن',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _ready ? _openAddress : null,
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
                filled: true,
                fillColor: const Color(0xFF111722),
              ),
            ),
          ),
          if (_loading)
            LinearProgressIndicator(
              value: _progress == 0 || _progress >= 100 ? null : _progress / 100,
              minHeight: 2,
            ),
          Expanded(
            child: !_ready || !_hasPage
                ? _homeContent(context)
                : WebViewWidget(controller: _webViewController!),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(_error!, style: const TextStyle(color: Color(0xFFFF7B84))),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(tooltip: 'بازگشت', onPressed: _canGoBack ? _goBack : null, icon: const Icon(Icons.arrow_back)),
              IconButton(tooltip: 'جلو', onPressed: _canGoForward ? _goForward : null, icon: const Icon(Icons.arrow_forward)),
              IconButton(tooltip: 'صفحهٔ خانه و پاک‌سازی نشست', onPressed: _goHome, icon: const Icon(Icons.home_outlined)),
              IconButton(
                tooltip: 'بارگذاری دوباره',
                onPressed: !_ready || !_hasPage ? null : () => _webViewController?.reload(),
                icon: const Icon(Icons.refresh),
              ),
              IconButton(tooltip: 'اتصال VPN', onPressed: () => widget.onOpenVpn?.call(context), icon: const Icon(Icons.shield)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _homeContent(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.travel_explore, size: 58, color: Color(0xFF52E6DF)),
              const SizedBox(height: 14),
              Text('جست‌وجو یا نشانی را وارد کن', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                _vpnState == 'connected'
                    ? 'سابقه و نشانک در برنامه ذخیره نمی‌شود. پاک‌سازی کوکی، حافظهٔ وب و دادهٔ محلی از منو در دسترس است.'
                    : 'برای جلوگیری از نشت IP، تا اتصال VPN هیچ سایتی بارگذاری نمی‌شود. برای قفل‌کردن کل گوشی، Always-on VPN و Block connections without VPN را هم در تنظیمات Android فعال کن.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF8992A5), height: 1.7),
              ),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () => _openAddress('https://html.duckduckgo.com'),
                icon: const Icon(Icons.search),
                label: const Text('بازکردن جست‌وجوی خصوصی'),
              ),
            ],
          ),
        ),
      );

  Future<void> _confirmClearData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('پاک‌کردن نشست خصوصی؟'),
        content: const Text('کوکی‌ها، حافظهٔ وب و دادهٔ محلی پاک می‌شوند و صفحه به خانه برمی‌گردد.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('پاک‌کردن')),
        ],
      ),
    );
    if (confirmed == true) await _goHome();
  }

  void _showPrivacyInfo() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حریم خصوصی این نسخه'),
        content: const Text(
          'مجوز موقعیت، دوربین و میکروفون صفحات وب رد می‌شود و کوکی شخص ثالث غیرفعال است. '
          'این مرورگر تا اتصال VPN وب‌گردی را قفل می‌کند و با قطع آن صفحه را پاک می‌کند. '
          'WebRTC در موتور WebView به‌طور اختصاصی غیرفعال نشده است. '
          'برای پوشش کل گوشی، در Android گزینه‌های Always-on VPN و Block connections without VPN را روشن کن. '
          'WebView اندروید است و حذف کامل اثرانگشت یا نشت در همهٔ شرایط تضمین نمی‌شود.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('متوجه شدم')),
        ],
      ),
    );
  }
}
