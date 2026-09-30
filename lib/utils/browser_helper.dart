import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../database/db_helper.dart';

/// UA, adblock e stealth compartilhados.
/// Padrão: lê SQLite primeiro (offline); opcionalmente sincroniza remoto.
class BrowserHelper {
  static const String kUserAgent = 'user_agent_custom';
  static const String kAdblockDomains = 'adblock_domains_list';
  static const String kAllowedDomains = 'allowed_domains_list';
  static const String kLastUpdate = 'browser_helper_last_update';

  static const String defaultUserAgentLinux =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  static const List<String> defaultAdDomains = [
    'dearthsongman.shop',
    'officeklafter.com',
    'loafedspences.com',
    'fauldspelikeyellows.qpon',
    'bhatrelime',
    'tcliktrc',
    'acquirepopdownloadnow',
    'doubleclick.net',
    'googlesyndication.com',
    'pagead2.googlesyndication',
    'bacchiccupule.qpon',
    '073m.com',
    'jjjjaaasss.com',
    'ohvbdellid.cfd',
    'acscdn.com',
    'pubadx.one',
    'magsrv.com',
    'a-ads.com',
    'diveinthebluesky.biz',
    'junior-shine.com',
    'chatmate.tv',
    'adjust.com',
    'pwpnotif.com',
    'acceptable.a-ads.com',
  ];

  /// Extras opcionais (a origem da sessão no screen é o principal).
  static const List<String> defaultAllowedDomains = [
    'nexustoons.com',
    'nx-toons.xyz',
    'leituramanga.net',
  ];

  static Future<String> getUserAgent() async {
    try {
      final saved = await DbHelper().getConfig(kUserAgent);
      if (saved != null && saved.trim().isNotEmpty) return saved.trim();
    } catch (e) {
      debugPrint('[BrowserHelper] getUserAgent DB: $e');
    }
    return defaultUserAgentLinux;
  }

  static Future<List<String>> getAdDomains() async {
    final fromDb = await _readStringList(kAdblockDomains);
    if (fromDb.isNotEmpty) {
      return {...defaultAdDomains, ...fromDb}.toList();
    }
    return List<String>.from(defaultAdDomains);
  }

  static Future<List<String>> getAllowedDomains() async {
    final fromDb = await _readStringList(kAllowedDomains);
    if (fromDb.isNotEmpty) {
      return {...defaultAllowedDomains, ...fromDb}.toList();
    }
    return List<String>.from(defaultAllowedDomains);
  }

  static Future<List<String>> _readStringList(String key) async {
    try {
      final raw = await DbHelper().getConfig(key);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[BrowserHelper] _readStringList($key): $e');
      return [];
    }
  }

  static String? originHostFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    return uri.host.toLowerCase();
  }

  static bool isSameOriginHost(String url, String originHost) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    final o = originHost.toLowerCase();
    if (o.isEmpty) return false;
    return host == o || host.endsWith('.$o');
  }

  static Future<bool> isAllowedUrl(String url) async {
    final lower = url.toLowerCase();
    if (lower.isEmpty ||
        lower.startsWith('about:') ||
        lower.startsWith('data:')) {
      return false;
    }
    final allowed = await getAllowedDomains();
    return allowed.any((d) => lower.contains(d.toLowerCase()));
  }

  static const String stealthScript = r'''
(function() {
  if (window.__mangaStealthInstalled) return;
  window.__mangaStealthInstalled = true;

  function safeDefine(obj, prop, value) {
    try {
      const desc = Object.getOwnPropertyDescriptor(obj, prop) ||
                   Object.getOwnPropertyDescriptor(Object.getPrototypeOf(obj), prop);
      if (!desc || desc.configurable) {
        Object.defineProperty(obj, prop, {
          get: function() { return value; },
          configurable: true
        });
      }
    } catch (e) {}
  }

  try { safeDefine(Navigator.prototype, 'webdriver', undefined); } catch (e) {}
  if (!window.chrome) {
    window.chrome = { runtime: {}, app: { isInstalled: false } };
  }
  try { safeDefine(navigator, 'languages', ['pt-BR', 'pt', 'en-US', 'en']); } catch (e) {}
  try { safeDefine(navigator, 'platform', 'Linux x86_64'); } catch (e) {}
  try { safeDefine(navigator, 'hardwareConcurrency', 8); } catch (e) {}
  try { safeDefine(navigator, 'deviceMemory', 8); } catch (e) {}

  try {
    const rejectMedia = function() {
      return Promise.reject(new DOMException('NotAllowedError', 'NotAllowedError'));
    };
    if (navigator.mediaDevices) {
      try {
        navigator.mediaDevices.getUserMedia = rejectMedia;
        navigator.mediaDevices.getDisplayMedia = rejectMedia;
        navigator.mediaDevices.enumerateDevices = function() {
          return Promise.resolve([]);
        };
      } catch (e) {}
    }
    if (navigator.getUserMedia) {
      try {
        navigator.getUserMedia = function(c, s, err) {
          if (err) err({ name: 'NotAllowedError' });
        };
      } catch (e) {}
    }
    if (navigator.webkitGetUserMedia) {
      try {
        navigator.webkitGetUserMedia = function(c, s, err) {
          if (err) err({ name: 'NotAllowedError' });
        };
      } catch (e) {}
    }
  } catch (e) {}
})();
''';

  /// [sessionOriginHost] = host de initialUrl (ex.: leituramanga.net).
  static Future<String> getAdBlockScript({String? sessionOriginHost}) async {
    final adDomains = await getAdDomains();
    final allowed = await getAllowedDomains();

    final allowSet = <String>{
      ...allowed,
      if (sessionOriginHost != null && sessionOriginHost.isNotEmpty)
        sessionOriginHost.toLowerCase(),
    };

    final adRe = adDomains.map(_escapeRegex).join('|');
    final allowRe = allowSet.map(_escapeRegex).join('|');

    return '''
(function() {
  if (window.__mangaAdBlockInstalled) return;
  window.__mangaAdBlockInstalled = true;

  window.open = function() { return null; };

  const AD_RE = /($adRe)/i;
  const ALLOWED = /($allowRe)/i;

  function isAd(url) {
    try { return AD_RE.test(String(url || '')); } catch (_) { return false; }
  }
  function isAllowedNav(url) {
    try { return ALLOWED.test(String(url || '')); } catch (_) { return false; }
  }

  const _fetch = window.fetch;
  window.fetch = function(input, init) {
    const url = (typeof input === 'string') ? input : (input && input.url);
    if (isAd(url)) return Promise.reject(new Error('blocked'));
    return _fetch.apply(this, arguments);
  };

  const XHR = window.XMLHttpRequest;
  window.XMLHttpRequest = function() {
    const xhr = new XHR();
    const open = xhr.open;
    xhr.open = function(method, url) {
      if (isAd(url)) throw new Error('blocked');
      return open.apply(this, arguments);
    };
    return xhr;
  };

  if (navigator.sendBeacon) {
    const _beacon = navigator.sendBeacon.bind(navigator);
    navigator.sendBeacon = function(url, data) {
      if (isAd(url)) return false;
      return _beacon(url, data);
    };
  }

  document.addEventListener('click', function(e) {
    let el = e.target;
    while (el && el.tagName !== 'A') el = el.parentElement;
    if (el && el.href && !isAllowedNav(el.href)) {
      e.preventDefault();
      e.stopPropagation();
    }
  }, true);
})();
''';
  }

  static String _escapeRegex(String s) {
    return s.replaceAllMapped(
      RegExp(r'[.*+?^${}()|[\]\\]'),
      (m) => '\\${m[0]}',
    );
  }

  static Future<bool> syncFromRemote(String endpointUrl) async {
    try {
      final response = await http
          .get(Uri.parse(endpointUrl))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return false;

      final data = jsonDecode(response.body);
      if (data is! Map) return false;

      final db = DbHelper();

      if (data['chrome_version'] != null) {
        final v = data['chrome_version'].toString();
        final ua =
            'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$v Safari/537.36';
        await db.setConfig(kUserAgent, ua);
      }
      if (data['user_agent'] is String &&
          (data['user_agent'] as String).isNotEmpty) {
        await db.setConfig(kUserAgent, data['user_agent'] as String);
      }
      if (data['blocked_domains'] is List) {
        await db.setConfig(
          kAdblockDomains,
          jsonEncode(data['blocked_domains']),
        );
      }
      if (data['allowed_domains'] is List) {
        await db.setConfig(
          kAllowedDomains,
          jsonEncode(data['allowed_domains']),
        );
      }

      await db.setConfig(kLastUpdate, DateTime.now().toIso8601String());
      return true;
    } catch (e) {
      debugPrint('[BrowserHelper] syncFromRemote: $e');
      return false;
    }
  }
}
