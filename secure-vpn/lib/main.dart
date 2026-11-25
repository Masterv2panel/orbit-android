// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';

import 'browser_screen.dart';
import 'vpn_service.dart';

void main() => runApp(const OrbitSecureApp());

class OrbitSecureApp extends StatelessWidget {
  const OrbitSecureApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Orbit Secure',
      debugShowCheckedModeBanner: false,
      locale: const Locale('fa', 'IR'),
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
          onOpenVpn: (context) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ConnectionScreen()),
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
    if (uri == null || !{'hysteria2', 'hy2'}.contains(uri.scheme.toLowerCase())) {
      throw const FormatException('لینک باید با hysteria2:// یا hy2:// شروع شود.');
    }
    if (uri.host.isEmpty) throw const FormatException('نشانی سرور در لینک نیست.');
    if (uri.userInfo.isEmpty) throw const FormatException('رمز اتصال در لینک نیست.');
    final insecure = uri.queryParameters['insecure']?.toLowerCase();
    if (insecure != null && !{'0', '1', 'true', 'false'}.contains(insecure)) {
      throw const FormatException('مقدار insecure باید 0/1 یا false/true باشد.');
    }
    final obfsType = uri.queryParameters['obfs'];
    final obfsPassword = uri.queryParameters['obfs-password'];
    if (obfsType != null && obfsType.isNotEmpty && obfsType != 'salamander') {
      throw const FormatException('نوع obfuscation این لینک پشتیبانی نمی‌شود.');
    }
    if ((obfsType == 'salamander') != (obfsPassword?.isNotEmpty ?? false)) {
      throw const FormatException('برای Salamander باید obfs-password هم باشد.');
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
          }
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
        }
      ],
      'outbounds': [outbound],
      'route': {
        'auto_detect_interface': true,
        'rules': [
          {'protocol': 'dns', 'action': 'hijack-dns'}
        ],
        'final': 'proxy',
      },
    };
    return jsonEncode(config);
  }
}

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

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
      if (mounted) setState(() => _state = status.state.toString().split('.').last);
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
            title: const Text('گواهی TLS بررسی نمی‌شود'),
            content: const Text(
              'این پروفایل هر گواهی سروری را می‌پذیرد. مهاجم واسطه می‌تواند اتصال را جعل یا شنود کند. '
              'فقط اگر به ارائه‌دهنده و سرور اعتماد داری ادامه بده.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('لغو')),
              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('می‌پذیرم و ادامه')),
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
      setState(() => _error = e.message ?? 'اتصال شروع نشد؛ تنظیمات یا سرور را بررسی کن.');
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
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    final stopwatch = Stopwatch()..start();
    try {
      final request = await client
          .getUrl(Uri.parse('https://www.gstatic.com/generate_204'))
          .timeout(const Duration(seconds: 12));
      request.followRedirects = false;
      final response = await request.close().timeout(const Duration(seconds: 12));
      await response.drain<void>();
      stopwatch.stop();
      if (!mounted) return;
      setState(() => _latency = response.statusCode == 204 ? '${stopwatch.elapsedMilliseconds} ms' : 'پاسخ نامعتبر');
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
    final statusColor = connected ? const Color(0xFF47D7A0) :
        connecting ? const Color(0xFFFFC46B) : const Color(0xFF8992A5);
    final statusText = connected ? 'متصل' : connecting ? 'در حال اتصال' :
        _state == 'error' ? 'خطا در اتصال' : 'قطع';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orbit Secure', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'مجوزها و اطلاعات برنامه',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showLicensePage(
              context: context,
              applicationName: 'Orbit Secure',
              applicationVersion: '0.1.0',
              applicationLegalese: 'GPL-3.0-or-later · بدون هیچ‌گونه ضمانت',
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  colors: [Color(0xFF182839), Color(0xFF15172B)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                border: Border.all(color: const Color(0x3352E6DF)),
              ),
              child: Column(
                children: [
                  Icon(connected ? Icons.shield : Icons.shield_outlined,
                      size: 52, color: statusColor),
                  const SizedBox(height: 10),
                  Text(statusText, style: TextStyle(fontSize: 22, color: statusColor,
                      fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(_profile == null ? 'پروفایل سرور وارد نشده' : '${_profile!.host}:${_profile!.port}',
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(color: Color(0xFFB9C1D3))),
                ],
              ),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _linkController,
              maxLines: _showLink ? 4 : 1,
              minLines: 1,
              obscureText: !_showLink,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'لینک Hysteria2',
                hintText: 'hysteria2://…',
                helperText: 'اطلاعات لینک فقط در حافظهٔ همین اجرا نگه داشته می‌شود.',
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
                suffixIcon: IconButton(
                  tooltip: _showLink ? 'پنهان‌کردن لینک' : 'نمایش موقت لینک',
                  icon: Icon(_showLink ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showLink = !_showLink),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _importLink,
              icon: const Icon(Icons.link),
              label: const Text('بررسی و بارگذاری لینک'),
            ),
            if (_profile != null) ...[
              const SizedBox(height: 8),
              Text(
                _profile!.tlsInsecure
                    ? 'هشدار: بررسی گواهی TLS خاموش است؛ اتصال در برابر حملهٔ واسطه آسیب‌پذیر است.'
                    : 'بررسی گواهی TLS روشن است.',
                style: TextStyle(
                  color: _profile!.tlsInsecure ? const Color(0xFFFF7B84) : Theme.of(context).colorScheme.secondary,
                  fontSize: 12,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!, style: const TextStyle(color: Color(0xFFFF7B84))),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: !_initialized || _busy ? null : _toggleConnection,
              icon: _busy || connecting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(connected ? Icons.stop : Icons.power_settings_new),
              label: Text(_busy || connecting ? 'در حال انجام…' : connected ? 'قطع اتصال' : 'اتصال VPN'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            ),
            if (connected) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _latencyBusy ? null : _testTunnelLatency,
                icon: _latencyBusy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.speed),
                label: Text(_latency == null ? 'سنجش تأخیر از داخل تونل' : 'تأخیر مسیر VPN: $_latency'),
              ),
            ],
            const SizedBox(height: 22),
            const Text(
              'با اتصال، اندروید درخواست مجوز VPN را نشان می‌دهد. فقط پس از تأیید تو، تونل شروع می‌شود. '
              'اتصال واقعی به سرور نیاز دارد و وضعیت «متصل» پس از گزارش هسته نمایش داده می‌شود.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF8992A5), height: 1.7, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
