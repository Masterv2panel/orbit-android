// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:sing_box_flutter/sing_box_flutter.dart';

/// Shares one Flutter API instance and one platform initialization across screens.
class OrbitVpnService {
  OrbitVpnService._();

  static final OrbitVpnService instance = OrbitVpnService._();

  final SingBoxFlutter api = SingBoxFlutter();
  Future<void>? _initialization;

  Future<void> initialize() async {
    final pending = _initialization;
    if (pending != null) return pending;

    final future = api.initialize(notificationTitle: 'Orbit Secure');
    _initialization = future;
    try {
      await future;
    } catch (_) {
      if (identical(_initialization, future)) _initialization = null;
      rethrow;
    }
  }
}
