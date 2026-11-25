// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';

import 'app_locale_controller.dart';
import 'browser_screen.dart';
import 'orbit_localization.dart';
import 'vpn_service.dart';

void main() => runApp(const OrbitSecureApp());

class OrbitSecureApp extends StatefulWidget {
  const OrbitSecureApp({super.key});

  @override
  State<OrbitSecureApp> createState() => _OrbitSecureAppState();
}

class _OrbitSecureAppState extends State<OrbitSecureApp> {
  final _localeController = OrbitLocaleController();

  @override
  void initState() {
    super.initState();
    _localeController.addListener(_onLocaleChanged);
    unawaited(_localeController.load());
  }

  void _onLocaleChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _localeController.removeListener(_onLocaleChanged);
    _localeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Orbit Secure',
    debugShowCheckedModeBanner: false,
    locale: _localeController.locale,
    supportedLocales: const [Locale('fa', 'IR'), Locale('en', 'US')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF52E6DF),
        brightness: Brightness.dark,
        surface: const Color(0xFF101522),
      ),
      scaffoldBackgroundColor: const Color(0xFF080B12),
      useMaterial3: true,
    ),
    home: BrowserScreen(
      onToggleLocale: _localeController.toggle,
      onOpenVpn: (context) {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                ConnectionScreen(onToggleLocale: _localeController.toggle),
          ),
        );
      },
    ),
  );
}

class HysteriaProfile {
  const HysteriaProfile({
    required this.host,
    required this.port,
    required this.password,
    required this.serverName,
    required this.tlsInsecure,
    this.obfsPassword,
    this.label,
  });

  final String host;
  final int port;
  final String password;
  final String serverName;
  final bool tlsInsecure;
  final String? obfsPassword;
  final String? label;

  static HysteriaProfile parse(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null ||
        !{'hysteria2', 'hy2'}.contains(uri.scheme.toLowerCase())) {
      throw const FormatException(
        'لینک باید با hysteria2:// یا hy2:// شروع شود.',
      );
    }
    if (uri.host.isEmpty)
      throw const FormatException('نشانی سرور در لینک نیست.');
    if (uri.userInfo.isEmpty)
      throw const FormatException('رمز اتصال در لینک نیست.');
    final insecure = uri.queryParameters['insecure']?.toLowerCase();
    if (insecure != null && !{'0', '1', 'true', 'false'}.contains(insecure)) {
      throw const FormatException(
        'مقدار insecure باید 0/1 یا false/true باشد.',
      );
    }
    final obfsType = uri.queryParameters['obfs'];
    final obfsPassword = uri.queryParameters['obfs-password'];
    if (obfsType != null && obfsType.isNotEmpty && obfsType != 'salamander') {
      throw const FormatException('نوع obfuscation این لینک پشتیبانی نمی‌شود.');
    }
    if ((obfsType == 'salamander') != (obfsPassword?.isNotEmpty ?? false)) {
      throw const FormatException(
        'برای Salamander باید obfs-password هم باشد.',
      );
    }

    return HysteriaProfile(
      host: uri.host,
      port: uri.hasPort ? uri.port : 443,
      password: Uri.decodeComponent(uri.userInfo),
      serverName: uri.queryParameters['sni']?.trim().isNotEmpty == true
          ? uri.queryParameters['sni']!.trim()
          : uri.host,
      tlsInsecure: insecure == '1' || insecure == 'true',
      obfsPassword: obfsType == 'salamander' ? obfsPassword : null,
      label: uri.fragment.isEmpty ? null : uri.fragment,
    );
  }

  String toSingBoxConfig() {
    final outbound = <String, Object?>{
      'type': 'hysteria2',
      'tag': 'proxy',
      'server': host,
      'server_port': port,
      'password': password,
      'tls': <String, Object?>{
        'enabled': true,
        'server_name': serverName,
        'insecure': tlsInsecure,
      },
      if (obfsPassword != null)
        'obfs': <String, Object?>{
          'type': 'salamander',
          'password': obfsPassword,
        },
    };

    final config = <String, Object?>{
      'log': {'level': 'warn'},
      'dns': {
        'servers': [
          {
            'type': 'udp',
            'tag': 'dns-via-proxy',
            'server': '1.1.1.1',
            'server_port': 53,
            'detour': 'proxy',
          },
        ],
        'final': 'dns-via-proxy',
        'strategy': 'prefer_ipv4',
      },
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'address': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
          'auto_route': true,
          'strict_route': true,
          'mtu': 1400,
        },
      ],
      'outbounds': [outbound],
      'route': {
        'auto_detect_interface': true,
        'rules': [
          {'protocol': 'dns', 'action': 'hijack-dns'},
        ],
        'final': 'proxy',
      },
    };
    return jsonEncode(config);
  }
}

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key, required this.onToggleLocale});

  final VoidCallback onToggleLocale;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen>
    with WidgetsBindingObserver {
  final _linkController = TextEditingController();
  final _vpnService = OrbitVpnService.instance;
  late final _vpn = _vpnService.api;
  StreamSubscription<dynamic>? _statusSubscription;
  HysteriaProfile? _profile;
  String _state = 'disconnected';
  String? _error;
  bool _busy = false;
  bool _initialized = false;
  bool _showLink = false;
  bool _latencyBusy = false;
  String? _latency;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _vpnService.initialize();
      _statusSubscription = _vpn.status.listen((status) {
        if (!mounted) return;
        setState(() => _state = status.state.toString().split('.').last);
      });
      final status = await _vpn.getStatus();
      if (!mounted) return;
      setState(() {
        _initialized = true;
        _state = status.state.toString().split('.').last;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _initialized = true;
          _error = 'راه‌اندازی هستهٔ اتصال ناموفق بود.';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatus();
  }

  Future<void> _refreshStatus() async {
    try {
      final status = await _vpn.getStatus();
      if (mounted)
        setState(() => _state = status.state.toString().split('.').last);
    } catch (_) {
      // Native service can be unavailable while Android is restarting it.
    }
  }

  void _importLink() {
    try {
      final profile = HysteriaProfile.parse(_linkController.text);
      setState(() {
        _profile = profile;
        _error = null;
      });
      FocusScope.of(context).unfocus();
    } on FormatException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'لینک اتصال قابل‌خواندن نیست.');
    }
  }

  Future<void> _toggleConnection() async {
    if (_busy || !_initialized) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_state == 'connected' || _state == 'connecting') {
        await _vpn.stop();
        if (mounted) setState(() => _state = 'disconnected');
        return;
      }
      final profile = _profile;
      if (profile == null) {
        setState(() => _error = 'اول لینک Hysteria2 سرور را وارد و بررسی کن.');
        return;
      }
      if (profile.tlsInsecure) {
        final accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: Text(orbitText(context, 'گواهی TLS بررسی نمی‌شود')),
            content: Text(
              orbitText(
                context,
                'این پروفایل هر گواهی سروری را می‌پذیرد. مهاجم واسطه می‌تواند اتصال را جعل یا شنود کند. '
                'فقط اگر به ارائه‌دهنده و سرور اعتماد داری ادامه بده.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(orbitText(context, 'لغو')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(orbitText(context, 'می‌پذیرم و ادامه')),
              ),
            ],
          ),
        );
        if (accepted != true) return;
      }
      final config = profile.toSingBoxConfig();
      await _vpn.checkConfig(config);
      final granted = await _vpn.requestPermission();
      if (!granted) {
        setState(() => _error = 'مجوز VPN در اندروید داده نشد.');
        return;
      }
      await _vpn.start(config: config, name: profile.label ?? 'Orbit Secure');
    } on PlatformException catch (e) {
      setState(
        () => _error =
            e.message ?? 'اتصال شروع نشد؛ تنظیمات یا سرور را بررسی کن.',
      );
    } catch (_) {
      setState(() => _error = 'اتصال شروع نشد؛ تنظیمات یا سرور را بررسی کن.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testTunnelLatency() async {
    if (_state != 'connected' || _latencyBusy) return;
    setState(() {
      _latencyBusy = true;
      _latency = null;
    });
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    final stopwatch = Stopwatch()..start();
    try {
      final request = await client
          .getUrl(Uri.parse('https://www.gstatic.com/generate_204'))
          .timeout(const Duration(seconds: 12));
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      await response.drain<void>();
      stopwatch.stop();
      if (!mounted) return;
      setState(
        () => _latency = response.statusCode == 204
            ? '${stopwatch.elapsedMilliseconds} ms'
            : 'پاسخ نامعتبر',
      );
    } catch (_) {
      if (mounted) setState(() => _latency = 'ناموفق');
    } finally {
      client.close(force: true);
      if (mounted) setState(() => _latencyBusy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkController.dispose();
    _statusSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _state == 'connected';
    final connecting = _state == 'connecting';
    final statusColor = connected
        ? const Color(0xFF47D7A0)
        : connecting
        ? const Color(0xFFFFC46B)
        : const Color(0xFF8992A5);
    final statusText = orbitText(
      context,
      connected
          ? 'متصل'
          : connecting
          ? 'در حال اتصال'
          : _state == 'error'
          ? 'خطا در اتصال'
          : 'قطع',
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Orbit Secure',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: orbitText(context, 'تغییر زبان'),
            icon: const Icon(Icons.translate_rounded),
            onPressed: widget.onToggleLocale,
          ),
          IconButton(
            tooltip: orbitText(context, 'مجوزها و اطلاعات برنامه'),
            icon: const Icon(Icons.info_outline),
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'Orbit Secure',
              applicationVersion: '0.1.0',
              applicationLegalese: orbitText(
                context,
                'GPL-3.0-or-later · بدون هیچ‌گونه ضمانت',
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF14313A),
                    Color(0xFF182033),
                    Color(0xFF111620),
                  ],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                border: Border.all(color: const Color(0x6652E6DF)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x2252E6DF),
                    blurRadius: 28,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0x2252E6DF),
                      border: Border.all(
                        color: statusColor.withOpacity(0.55),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      connected ? Icons.shield_rounded : Icons.shield_outlined,
                      size: 42,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 24,
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _profile == null
                        ? orbitText(context, 'پروفایل سرور وارد نشده')
                        : '${_profile!.host}:${_profile!.port}',
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      color: Color(0xFFB9C1D3),
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x22101522),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, size: 8, color: statusColor),
                        const SizedBox(width: 8),
                        Text(
                          orbitText(
                            context,
                            connected ? 'تونل فعال' : 'تونل امن Hysteria2',
                          ),
                          style: const TextStyle(
                            color: Color(0xFFD8E5E8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text(
              orbitText(context, 'پروفایل اتصال'),
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _linkController,
              maxLines: _showLink ? 4 : 1,
              minLines: 1,
              obscureText: !_showLink,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: orbitText(context, 'لینک Hysteria2'),
                hintText: 'hysteria2://…',
                helperText: orbitText(
                  context,
                  'اطلاعات لینک فقط در حافظهٔ همین اجرا نگه داشته می‌شود.',
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                filled: true,
                fillColor: const Color(0xFF111722),
                alignLabelWithHint: true,
                suffixIcon: IconButton(
                  tooltip: orbitText(
                    context,
                    _showLink ? 'پنهان‌کردن لینک' : 'نمایش موقت لینک',
                  ),
                  icon: Icon(
                    _showLink ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () => setState(() => _showLink = !_showLink),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _importLink,
              icon: const Icon(Icons.link),
              label: Text(orbitText(context, 'بررسی و بارگذاری لینک')),
            ),
            if (_profile != null) ...[
              const SizedBox(height: 8),
              Text(
                orbitText(
                  context,
                  _profile!.tlsInsecure
                      ? 'هشدار: بررسی گواهی TLS خاموش است؛ اتصال در برابر حملهٔ واسطه آسیب‌پذیر است.'
                      : 'بررسی گواهی TLS روشن است.',
                ),
                style: TextStyle(
                  color: _profile!.tlsInsecure
                      ? const Color(0xFFFF7B84)
                      : Theme.of(context).colorScheme.secondary,
                  fontSize: 12,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                orbitText(context, _error!),
                style: const TextStyle(color: Color(0xFFFF7B84)),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: !_initialized || _busy ? null : _toggleConnection,
              icon: _busy || connecting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(connected ? Icons.stop : Icons.power_settings_new),
              label: Text(
                orbitText(
                  context,
                  _busy || connecting
                      ? 'در حال انجام…'
                      : connected
                      ? 'قطع اتصال'
                      : 'اتصال VPN',
                ),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
            ),
            if (connected) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _latencyBusy ? null : _testTunnelLatency,
                icon: _latencyBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.speed),
                label: Text(
                  _latency == null
                      ? orbitText(context, 'سنجش تأخیر از داخل تونل')
                      : orbitTextPair(
                          context,
                          'تأخیر مسیر VPN: $_latency',
                          'VPN route latency: ${orbitText(context, _latency!)}',
                        ),
                ),
              ),
            ],
            const SizedBox(height: 22),
            Text(
              orbitText(
                context,
                'با اتصال، اندروید درخواست مجوز VPN را نشان می‌دهد. فقط پس از تأیید تو، تونل شروع می‌شود. '
                'اتصال واقعی به سرور نیاز دارد و وضعیت «متصل» پس از گزارش هسته نمایش داده می‌شود.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF8992A5),
                height: 1.7,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
