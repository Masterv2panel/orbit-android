// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';
import 'dart:convert';
import 'dart:io';

class VpnTimezoneService {
  static const lookupUri = 'https://ipapi.co/timezone/';
  static final _validZone = RegExp(r'^(?:UTC|GMT|[A-Za-z_+-]+(?:/[A-Za-z0-9_+.-]+)+)$');

  Future<String> lookupExitTimezone() async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 7);
    try {
      final request = await client
          .getUrl(Uri.parse(lookupUri))
          .timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.acceptHeader, 'text/plain');
      final response = await request.close().timeout(const Duration(seconds: 8));
      final body = (await response.transform(utf8.decoder).join())
          .trim()
          .replaceAll('\r', '')
          .replaceAll('\n', '');
      if (response.statusCode != HttpStatus.ok || !_validZone.hasMatch(body)) {
        throw const FormatException('منطقهٔ زمانی از IP خروجی VPN دریافت نشد.');
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }

  String buildDocumentStartScript(String ianaTimezone) {
    if (!_validZone.hasMatch(ianaTimezone)) {
      throw const FormatException('شناسهٔ IANA منطقهٔ زمانی معتبر نیست.');
    }
    final zone = jsonEncode(ianaTimezone);
    return '''
(() => {
  if (globalThis.__orbitVpnTimezoneInstalled) return;
  const zone = $zone;
  const NativeDateTimeFormat = Intl.DateTimeFormat;
  const nativeFormat = (locales, options) => {
    const opts = options == null ? {} : { ...options };
    if (opts.timeZone == null) opts.timeZone = zone;
    return new NativeDateTimeFormat(locales, opts);
  };
  function OrbitDateTimeFormat(locales, options) {
    return nativeFormat(locales, options);
  }
  OrbitDateTimeFormat.prototype = NativeDateTimeFormat.prototype;
  Object.setPrototypeOf(OrbitDateTimeFormat, NativeDateTimeFormat);
  Object.defineProperty(Intl, 'DateTimeFormat', {
    value: OrbitDateTimeFormat, configurable: false, writable: false
  });

  const partsFormatter = new NativeDateTimeFormat('en-US-u-ca-gregory-nu-latn', {
    timeZone: zone, year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
    weekday: 'short', hourCycle: 'h23'
  });
  const partsFor = (date) => Object.fromEntries(
    partsFormatter.formatToParts(date).filter((part) => part.type !== 'literal')
      .map((part) => [part.type, part.value])
  );
  const numberPart = (date, name) => Number(partsFor(date)[name]);
  const offsetFor = (date) => {
    const p = partsFor(date);
    const asUtc = Date.UTC(Number(p.year), Number(p.month) - 1, Number(p.day),
      Number(p.hour), Number(p.minute), Number(p.second));
    return Math.round((date.getTime() - asUtc) / 60000);
  };
  const defineMethod = (name, method) => Object.defineProperty(Date.prototype, name, {
    value: method, configurable: true, writable: true
  });
  defineMethod('getTimezoneOffset', function() { return offsetFor(this); });
  defineMethod('getFullYear', function() { return numberPart(this, 'year'); });
  defineMethod('getYear', function() { return numberPart(this, 'year') - 1900; });
  defineMethod('getMonth', function() { return numberPart(this, 'month') - 1; });
  defineMethod('getDate', function() { return numberPart(this, 'day'); });
  defineMethod('getHours', function() { return numberPart(this, 'hour'); });
  defineMethod('getMinutes', function() { return numberPart(this, 'minute'); });
  defineMethod('getSeconds', function() { return numberPart(this, 'second'); });
  defineMethod('getMilliseconds', function() { return this.getTime() % 1000; });
  defineMethod('getDay', function() {
    const p = partsFor(this);
    return new Date(Date.UTC(Number(p.year), Number(p.month) - 1, Number(p.day))).getUTCDay();
  });

  const formatLocal = (date, locales, options) => {
    const opts = options == null ? {} : { ...options };
    if (opts.timeZone == null) opts.timeZone = zone;
    return new NativeDateTimeFormat(locales, opts).format(date);
  };
  defineMethod('toLocaleString', function(locales, options) {
    return formatLocal(this, locales, options);
  });
  defineMethod('toLocaleDateString', function(locales, options) {
    return formatLocal(this, locales, { year: 'numeric', month: 'numeric', day: 'numeric', ...options });
  });
  defineMethod('toLocaleTimeString', function(locales, options) {
    return formatLocal(this, locales, { hour: 'numeric', minute: 'numeric', second: 'numeric', ...options });
  });
  defineMethod('toString', function() {
    return formatLocal(this, 'en-US', {
      weekday: 'short', year: 'numeric', month: 'short', day: '2-digit',
      hour: '2-digit', minute: '2-digit', second: '2-digit', timeZoneName: 'short', hourCycle: 'h23'
    });
  });
  defineMethod('toDateString', function() {
    return formatLocal(this, 'en-US', { weekday: 'short', year: 'numeric', month: 'short', day: '2-digit' });
  });
  defineMethod('toTimeString', function() {
    return formatLocal(this, 'en-US', { hour: '2-digit', minute: '2-digit', second: '2-digit', timeZoneName: 'short', hourCycle: 'h23' });
  });
  Object.defineProperty(globalThis, '__orbitVpnTimezone', { value: zone });
  Object.defineProperty(globalThis, '__orbitVpnTimezoneInstalled', { value: true });
})();
''';
  }
}
