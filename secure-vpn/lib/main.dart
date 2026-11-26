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
        ? const Color(0xFF54E0B0)
        : connecting
        ? const Color(0xFFFFC46B)
        : const Color(0xFF93A1B8);
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
    final scheme = Theme.of(context).colorScheme;
    final cardDecoration = BoxDecoration(
      color: const Color(0xFF101722),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFF202C3B)),
    );

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Text(
          'Orbit Secure',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .2),
        ),
        actions: [
          IconButton(
            tooltip: orbitText(context, 'تغییر زبان'),
            icon: const Icon(Icons.translate_rounded),
            onPressed: widget.onToggleLocale,
          ),
          IconButton(
            tooltip: orbitText(context, 'مجوزها و اطلاعات برنامه'),
            icon: const Icon(Icons.info_outline_rounded),
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
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 32),
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 22),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF10343B),
                        Color(0xFF142337),
                        Color(0xFF101722),
                      ],
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                    ),
                    border: Border.all(color: const Color(0x5552E6DF)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1F36D6D0),
                        blurRadius: 30,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: statusColor.withOpacity(.10),
                          border: Border.all(
                            color: statusColor.withOpacity(.55),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          connected
                              ? Icons.shield_rounded
                              : Icons.shield_outlined,
                          size: 38,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(height: 15),
                      Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 25,
                          color: statusColor,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        _profile == null
                            ? orbitText(context, 'پروفایل سرور وارد نشده')
                            : '${_profile!.host}:${_profile!.port}',
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFBECADB),
                          fontSize: 14,
                          letterSpacing: .25,
                        ),
                      ),
                      const SizedBox(height: 15),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x25101522),
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
                                color: Color(0xFFD9E5ED),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 25),
                Text(
                  orbitText(context, 'پروفایل اتصال'),
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 11),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: cardDecoration,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _linkController,
                        maxLines: _showLink ? 4 : 1,
                        minLines: 1,
                        obscureText: !_showLink,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.url,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          labelText: orbitText(context, 'لینک Hysteria2'),
                          hintText: 'hysteria2://…',
                          helperText: orbitText(
                            context,
                            'اطلاعات لینک فقط در حافظهٔ همین اجرا نگه داشته می‌شود.',
                          ),
                          helperMaxLines: 2,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: const BorderSide(
                              color: Color(0xFF344255),
                            ),
                          ),
                          filled: true,
                          fillColor: const Color(0xFF0B111A),
                          alignLabelWithHint: true,
                          suffixIcon: IconButton(
                            tooltip: orbitText(
                              context,
                              _showLink ? 'پنهان‌کردن لینک' : 'نمایش موقت لینک',
                            ),
                            icon: Icon(
                              _showLink
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                            ),
                            onPressed: () =>
                                setState(() => _showLink = !_showLink),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _importLink,
                        icon: const Icon(Icons.link_rounded),
                        label: Text(
                          orbitText(context, 'بررسی و بارگذاری لینک'),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                      if (_profile != null) ...[
                        const SizedBox(height: 12),
                        _NoticeRow(
                          color: _profile!.tlsInsecure
                              ? const Color(0xFFFF858B)
                              : const Color(0xFF54D6AA),
                          icon: _profile!.tlsInsecure
                              ? Icons.warning_amber_rounded
                              : Icons.verified_user_outlined,
                          text: orbitText(
                            context,
                            _profile!.tlsInsecure
                                ? 'هشدار: بررسی گواهی TLS خاموش است؛ اتصال در برابر حملهٔ واسطه آسیب‌پذیر است.'
                                : 'بررسی گواهی TLS روشن است.',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 13),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF321D28),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0x66FF7583)),
                    ),
                    child: _NoticeRow(
                      color: const Color(0xFFFF8991),
                      icon: Icons.error_outline_rounded,
                      text: orbitText(context, _error!),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: !_initialized || _busy ? null : _toggleConnection,
                  icon: _busy || connecting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          connected
                              ? Icons.stop_rounded
                              : Icons.power_settings_new_rounded,
                        ),
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
                    backgroundColor: connected
                        ? const Color(0xFF243442)
                        : const Color(0xFF087F87),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(17),
                    ),
                  ),
                ),
                if (connected) ...[
                  const SizedBox(height: 12),
                  Container(
                    decoration: cardDecoration,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: _latencyBusy ? null : _testTunnelLatency,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 5,
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.speed_rounded, color: scheme.secondary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _latency == null
                                    ? orbitText(
                                        context,
                                        'سنجش تأخیر از داخل تونل',
                                      )
                                    : orbitTextPair(
                                        context,
                                        'تأخیر مسیر VPN: $_latency',
                                        'VPN route latency: ${orbitText(context, _latency!)}',
                                      ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (_latencyBusy)
                              const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            else
                              IconButton(
                                tooltip: orbitText(
                                  context,
                                  'سنجش تأخیر از داخل تونل',
                                ),
                                onPressed: _testTunnelLatency,
                                icon: const Icon(Icons.refresh_rounded),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 21),
                Text(
                  orbitText(
                    context,
                    'با اتصال، اندروید درخواست مجوز VPN را نشان می‌دهد. فقط پس از تأیید تو، تونل شروع می‌شود. '
                    'اتصال واقعی به سرور نیاز دارد و وضعیت «متصل» پس از گزارش هسته نمایش داده می‌شود.',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF929FB1),
                    height: 1.7,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({
    required this.color,
    required this.icon,
    required this.text,
  });

  final Color color;
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 19, color: color),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          text,
          style: TextStyle(color: color, fontSize: 12, height: 1.5),
        ),
      ),
    ],
  );
}
