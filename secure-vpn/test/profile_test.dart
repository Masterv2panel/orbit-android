// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orbit_secure/main.dart';

void main() {
  group('HysteriaProfile', () {
    test('parses a standard Hysteria2 URI and uses port 443 by default', () {
      final profile = HysteriaProfile.parse('hysteria2://secret@example.com?sni=cdn.example.com#home');
      expect(profile.host, 'example.com');
      expect(profile.port, 443);
      expect(profile.password, 'secret');
      expect(profile.serverName, 'cdn.example.com');
      expect(profile.label, 'home');
    });

    test('rejects links that disable certificate verification', () {
      expect(
        () => HysteriaProfile.parse('hy2://secret@example.com:8443?insecure=1'),
        throwsA(isA<FormatException>()),
      );
    });

    test('maps Salamander obfuscation into sing-box outbound config', () {
      final profile = HysteriaProfile.parse(
        'hysteria2://p%40ss@example.com:8443?obfs=salamander&obfs-password=mask',
      );
      final config = jsonDecode(profile.toSingBoxConfig()) as Map<String, dynamic>;
      final outbound = (config['outbounds'] as List).single as Map<String, dynamic>;
      expect(outbound['type'], 'hysteria2');
      expect(outbound['password'], 'p@ss');
      expect(outbound['server_port'], 8443);
      expect(outbound['tls']['enabled'], isTrue);
      expect(outbound['obfs']['type'], 'salamander');
      expect((config['route'] as Map)['final'], 'proxy');
    });

    test('rejects unsupported URI schemes and incomplete Salamander settings', () {
      expect(() => HysteriaProfile.parse('https://example.com'), throwsA(isA<FormatException>()));
      expect(
        () => HysteriaProfile.parse('hy2://secret@example.com?obfs=salamander'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
