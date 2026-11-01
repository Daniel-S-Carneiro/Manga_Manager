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

  /// Extrai número de capítulo de título / texto curto.
  /// Exemplos: "Cap. 103", "Capítulo 16", "Chapter 16", "Cap 918"
  static int? parseChapterNumber(String? text) {
    if (text == null || text.trim().isEmpty) return null;
    final t = text.toLowerCase();

    final patterns = <RegExp>[
      RegExp(r'cap[ií]tulo\s*[.:]?\s*(\d+)', caseSensitive: false),
      RegExp(r'\bcap\.?\s*(\d+)', caseSensitive: false),
      RegExp(r'\bchapter\s*[.:]?\s*(\d+)', caseSensitive: false),
      RegExp(r'\bch\.?\s*(\d+)\b', caseSensitive: false),
      RegExp(r'\bcapitulo\s*[.:]?\s*(\d+)', caseSensitive: false),
    ];

    for (final re in patterns) {
      final m = re.firstMatch(t);
      if (m != null) {
        return int.tryParse(m.group(1)!);
      }
    }
    return null;
  }

  static int? parseChapterFromUrl(String? url) {
    if (url == null || url.trim().isEmpty) return null;
    final patterns = <RegExp>[
      RegExp(r'/chapter[s]?/(\d+)/?', caseSensitive: false),
      RegExp(r'cap[ií]tulo[_-]?(\d+)/?(?:\?|#|$)', caseSensitive: false),
      RegExp(r'/cap[ií]tulo/(\d+)/?', caseSensitive: false),
      RegExp(r'[?&]chapter=(\d+)', caseSensitive: false),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(url);
      if (m != null) return int.tryParse(m.group(1)!);
    }
    return null;
  }

  /// Title primeiro; se falhar, tenta URL.
  static int? parseChapter({String? title, String? url}) {
    return parseChapterNumber(title) ?? parseChapterFromUrl(url);
  }

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
    'hdwetwindle.com',
    'goferyouthy.cfd',
    'unamendpongids.qpon',
    'adservice.google.com.br',
    'adservice.google.com',
    'googletagservices.com',
    'google-analytics.com',
    'static.cloudflareinsights.com',
  ];

  /// Extras opcionais (a origem da sessão no screen é o principal).
  static const List<String> defaultAllowedDomains = [
    'nexustoons.com',
    'nx-toons.xyz',
    'leituramanga.net',
  ];

  // ---------------------------------------------------------------------------
  // USER AGENT
  // ---------------------------------------------------------------------------

  /// Mantido por compatibilidade: sempre devolve algo (padrão Linux).
  static Future<String> getUserAgent() async {
    try {
      final saved = await DbHelper().getConfig(kUserAgent);
      if (saved != null && saved.trim().isNotEmpty) return saved.trim();
    } catch (e) {
      debugPrint('[BrowserHelper] getUserAgent DB: $e');
    }
    return defaultUserAgentLinux;
  }

  /// UA personalizado salvo no banco, ou null se não houver nenhum.
  static Future<String?> getCustomUserAgent() async {
    try {
      final saved = await DbHelper().getConfig(kUserAgent);
      if (saved != null && saved.trim().isNotEmpty) return saved.trim();
    } catch (e) {
      debugPrint('[BrowserHelper] getCustomUserAgent DB: $e');
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // LISTAS DE DOMÍNIOS
  // ---------------------------------------------------------------------------

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

  /// Verifica pelo HOST (não pela URL inteira), para que um domínio permitido
  /// escondido em query string / caminho não libere a navegação.
  /// - Entrada com ponto (ex.: 'nexustoons.com'): host igual ou subdomínio.
  /// - Entrada sem ponto (ex.: 'nexustoons'): aparece como trecho do host.
  static bool hostMatchesAllowed(String url, Iterable<String> domains) {
    final host = originHostFromUrl(url);
    if (host == null) return false;

    for (final raw in domains) {
      final d = raw.trim().toLowerCase();
      if (d.isEmpty) continue;
      if (d.contains('.')) {
        if (host == d || host.endsWith('.$d')) return true;
      } else if (host.contains(d)) {
        return true;
      }
    }
    return false;
  }

  static Future<bool> isAllowedUrl(String url) async {
    final lower = url.toLowerCase();
    if (lower.isEmpty ||
        lower.startsWith('about:') ||
        lower.startsWith('data:')) {
      return false;
    }
    final allowed = await getAllowedDomains();
    return hostMatchesAllowed(url, allowed);
  }

  // ---------------------------------------------------------------------------
  // STEALTH
  // ---------------------------------------------------------------------------

  /// Script de stealth original (mantido sem alterações: usado em iOS, Linux
  /// e quando o interruptor do Android coerente estiver desligado).
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

  /// Stealth coerente para ANDROID (WebView do Chromium).
  /// Diferente do [stealthScript], NÃO falseia platform / languages /
  /// hardwareConcurrency / deviceMemory / webdriver: o WebView já devolve os
  /// valores reais do aparelho, que batem com o UA de Chrome Android. O que ele
  /// faz é remover o que denuncia "app embutido":
  ///  - a marca "Android WebView" em navigator.userAgentData (client hints);
  ///  - as pontes window.Flutter / window.Android;
  ///  - captura de mídia (mantido do script original, evita pedidos de permissão).
  static const String stealthScriptAndroid = r'''
(function() {
  if (window.__mangaStealthAndroid) return;
  window.__mangaStealthAndroid = true;

  // 1) navigator.userAgentData: troca a marca "Android WebView" por "Google Chrome"
  try {
    var uad = navigator.userAgentData;
    if (uad) {
      var proto = Object.getPrototypeOf(uad);
      var fixBrands = function(list) {
        if (!Array.isArray(list)) return list;
        return list.map(function(b) {
          return (b && b.brand === 'Android WebView')
            ? { brand: 'Google Chrome', version: b.version }
            : b;
        });
      };

      var brandsDesc = Object.getOwnPropertyDescriptor(proto, 'brands');
      if (brandsDesc && brandsDesc.get) {
        Object.defineProperty(proto, 'brands', {
          get: function() { return fixBrands(brandsDesc.get.call(this)); },
          enumerable: brandsDesc.enumerable,
          configurable: true
        });
      }

      var origHigh = proto.getHighEntropyValues;
      if (typeof origHigh === 'function') {
        proto.getHighEntropyValues = function(hints) {
          return origHigh.call(this, hints).then(function(v) {
            if (v && v.brands) v.brands = fixBrands(v.brands);
            if (v && v.fullVersionList) v.fullVersionList = fixBrands(v.fullVersionList);
            return v;
          });
        };
      }

      var origJson = proto.toJSON;
      if (typeof origJson === 'function') {
        proto.toJSON = function() {
          var j = origJson.call(this);
          if (j && j.brands) j.brands = fixBrands(j.brands);
          return j;
        };
      }
    }
  } catch (e) {}

  // 2) window.chrome (o Chrome real tem; o WebView geralmente não)
  if (!window.chrome) {
    window.chrome = { runtime: {}, app: { isInstalled: false } };
  }

  // 3) Captura de mídia bloqueada (evita pedidos de permissão)
  try {
    var rejectMedia = function() {
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

  // 4) Pontes que denunciam app embutido
  try { delete window.Flutter; } catch (e) {}
  try { delete window.Android; } catch (e) {}
})();
''';

  // ---------------------------------------------------------------------------
  // ADBLOCK (JS)
  // ---------------------------------------------------------------------------

  /// [sessionOriginHost] = host de initialUrl (ex.: leituramanga.net).
  /// [adDomains] / [allowedDomains] podem ser passados para evitar reler o banco.
  ///
  /// As listas vão para o JS como JSON e a comparação é feita pelo HOST
  /// (nada de regex interpolada, então entradas com "/" não quebram o script).
  static Future<String> getAdBlockScript({
    String? sessionOriginHost,
    List<String>? adDomains,
    List<String>? allowedDomains,
  }) async {
    final ads = adDomains ?? await getAdDomains();
    final allowed = allowedDomains ?? await getAllowedDomains();

    final allowSet = <String>{
      ...allowed.map((e) => e.trim().toLowerCase()),
      if (sessionOriginHost != null && sessionOriginHost.isNotEmpty)
        sessionOriginHost.toLowerCase(),
    }..removeWhere((e) => e.isEmpty);

    final adList = ads
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    final adJson = jsonEncode(adList);
    final allowJson = jsonEncode(allowSet.toList());

    return '''
(function() {
  // Não mexe em iframes de captcha / desafio anti-bot (podem detectar patches)
  try {
    var h0 = location.hostname.toLowerCase();
    if (h0 === 'challenges.cloudflare.com' ||
        h0 === 'hcaptcha.com' || h0.endsWith('.hcaptcha.com') ||
        h0.endsWith('recaptcha.net') ||
        (h0.endsWith('google.com') && location.pathname.indexOf('/recaptcha') === 0)) {
      return;
    }
  } catch (_) {}

  // Flag estrita para evitar Memory Leak de múltiplos listeners
  if (window.__mangaAdBlockInstalled) return;
  window.__mangaAdBlockInstalled = true;

  window.open = function() { return null; };

  const AD_LIST = $adJson;
  const ALLOW_LIST = $allowJson;

  function hostOf(url) {
    try { return new URL(String(url || ''), location.href).hostname.toLowerCase(); }
    catch (_) { return ''; }
  }

  // Entrada sem "/" casa por trecho do host; entrada com "/" casa na URL inteira
  function isAd(url) {
    const s = String(url || '').toLowerCase();
    const h = hostOf(s);
    for (let i = 0; i < AD_LIST.length; i++) {
      const e = AD_LIST[i];
      if (e.indexOf('/') >= 0) {
        if (s.indexOf(e) >= 0) return true;
      } else if (h && h.indexOf(e) >= 0) {
        return true;
      }
    }
    return false;
  }

  // Entrada com ponto: host igual ou subdomínio; sem ponto: trecho do host
  function isAllowedNav(url) {
    const h = hostOf(url);
    if (!h) return false;
    for (let i = 0; i < ALLOW_LIST.length; i++) {
      const d = ALLOW_LIST[i];
      if (d.indexOf('.') >= 0) {
        if (h === d || h.endsWith('.' + d)) return true;
      } else if (h.indexOf(d) >= 0) {
        return true;
      }
    }
    return false;
  }

  const _fetch = window.fetch;
  if (_fetch) {
    window.fetch = function(input, init) {
      let url = '';
      try {
        url = (typeof Request !== 'undefined' && input instanceof Request)
          ? input.url
          : String(input);
      } catch (_) {}
      if (isAd(url)) {
        return Promise.resolve(new Response(new Blob(), {status: 200, statusText: 'OK'}));
      }
      return _fetch.apply(this, arguments);
    };
  }

  // Patch no protótipo (mantém instanceof, constantes e setRequestHeader funcionando)
  try {
    const xhrProto = window.XMLHttpRequest && window.XMLHttpRequest.prototype;
    if (xhrProto) {
      const _open = xhrProto.open;
      const _send = xhrProto.send;
      xhrProto.open = function(method, url) {
        this.__mangaBlocked = isAd(url);
        return _open.apply(this, arguments);
      };
      xhrProto.send = function() {
        if (this.__mangaBlocked) return; // Aborta silenciosamente
        return _send.apply(this, arguments);
      };
    }
  } catch (_) {}

  if (navigator.sendBeacon) {
    const _beacon = navigator.sendBeacon.bind(navigator);
    navigator.sendBeacon = function(url, data) {
      if (isAd(url)) return false;
      return _beacon(url, data);
    };
  }

  // Intercepta cliques abusivos na fase de captura (true)
  document.addEventListener('click', function(e) {
    const t = e.target;
    const el = (t && t.closest) ? t.closest('a') : null;
    if (!el) return;

    const href = (typeof el.href === 'string')
      ? el.href
      : ((el.href && el.href.baseVal) || '');
    if (!href) return;

    // Bloqueia navegação não permitida
    if (!isAllowedNav(href)) {
      e.preventDefault();
      e.stopPropagation();
      return;
    }
    // Tentativa de abrir nova aba (_blank pop-unders): mesma aba, link permitido
    if (el.target === '_blank') {
      e.preventDefault();
      e.stopPropagation();
      window.location.href = href;
    }
  }, true);
})();
''';
  }

  // ---------------------------------------------------------------------------
  // SYNC REMOTO
  // ---------------------------------------------------------------------------

  static final RegExp _chromeVersionRe = RegExp(r'^\d{2,3}(\.\d{1,5}){0,3}$');
  static final RegExp _domainEntryRe = RegExp(
    r'^[a-z0-9][a-z0-9._-]*[a-z0-9](/\S*)?$',
  );

  static bool _isValidDomainEntry(String s) {
    return s.length >= 3 && s.length <= 200 && _domainEntryRe.hasMatch(s);
  }

  static bool _isValidUserAgent(String s) {
    return s.startsWith('Mozilla/5.0') && s.length <= 400;
  }

  static List<String> _sanitizeDomainList(List raw) {
    return raw
        .whereType<String>()
        .map((s) => s.trim().toLowerCase())
        .where(_isValidDomainEntry)
        .toSet()
        .take(2000)
        .toList();
  }

  static Future<bool> syncFromRemote(String endpointUrl) async {
    try {
      final endpoint = Uri.tryParse(endpointUrl);
      if (endpoint == null || !endpoint.hasScheme || endpoint.host.isEmpty) {
        return false;
      }
      // Em release só aceita https (os dados remotos ampliam a lista de
      // navegação permitida e entram no JS injetado).
      if (endpoint.scheme != 'https' && !kDebugMode) {
        debugPrint(
          '[BrowserHelper] syncFromRemote: endpoint precisa ser https',
        );
        return false;
      }

      final response = await http
          .get(endpoint)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return false;

      final data = jsonDecode(response.body);
      if (data is! Map) return false;

      final db = DbHelper();

      final chromeVersion = data['chrome_version']?.toString();
      if (chromeVersion != null && _chromeVersionRe.hasMatch(chromeVersion)) {
        final ua =
            'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$chromeVersion Safari/537.36';
        await db.setConfig(kUserAgent, ua);
      }

      final customUa = data['user_agent'];
      if (customUa is String && _isValidUserAgent(customUa)) {
        await db.setConfig(kUserAgent, customUa);
      }

      // Só entradas com formato válido de domínio/palavra-chave são gravadas
      if (data['blocked_domains'] is List) {
        final validBlocked = _sanitizeDomainList(
          data['blocked_domains'] as List,
        );
        await db.setConfig(kAdblockDomains, jsonEncode(validBlocked));
      }

      if (data['allowed_domains'] is List) {
        final validAllowed = _sanitizeDomainList(
          data['allowed_domains'] as List,
        );
        await db.setConfig(kAllowedDomains, jsonEncode(validAllowed));
      }

      await db.setConfig(kLastUpdate, DateTime.now().toIso8601String());
      return true;
    } catch (e) {
      debugPrint('[BrowserHelper] syncFromRemote: $e');
      return false;
    }
  }
}
