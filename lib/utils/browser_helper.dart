import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../database/db_helper.dart';
import 'config_rolagem.dart';

/// User agent, bloqueio de anúncios e scripts de compatibilidade dos leitores.
/// As listas vêm do código e do banco (SQLite); nada é baixado de fora.
class BrowserHelper {
  static const String kUserAgent = 'user_agent_custom';
  static const String kAdblockDomains = 'adblock_domains_list';
  static const String kAllowedDomains = 'allowed_domains_list';

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

  /// Texto do primeiro cabeçalho da página (ou o título), usado para achar o
  /// capítulo quando o título da aba não traz o número.
  static const String scriptTextoCabecalho = r'''
(function() {
  var h = document.querySelector('h1, h2, header, [class*="title"], [class*="chapter"]');
  if (!h) return document.title || '';
  return (h.innerText || h.textContent || '').slice(0, 200);
})();
''';

  /// Lê o que o adblock anotou em modo diagnóstico (JSON ou "null").
  static const String scriptLerDiagnostico =
      'JSON.stringify(window.__mangaDiag || null)';

  /// Bloqueia cliques em iframes e em elementos com classe/id de anúncio
  /// (só desktop). Casa "ad", "ads", "banner"... só como palavra inteira
  /// (antes, 'ad' pegava "read", "reader", "header", "loader", "download"...).
  static const String cliqueAgressivoScript = r'''
(function() {
  if (window.__mangaAggressiveClick) return;
  window.__mangaAggressiveClick = true;

  var AD_TOKEN = /(^|[\s_-])(ad|ads|adv|advert|advertisement|adsbygoogle|banner|popup)([\s_-]|$)/;

  document.addEventListener('click', function(e) {
    var target = e.target;
    if (!target) return;

    var id = String(target.id || '').toLowerCase();
    var cls = String((target.getAttribute && target.getAttribute('class')) || '').toLowerCase();
    var tag = String(target.tagName || '').toUpperCase();

    if (tag === 'IFRAME' || AD_TOKEN.test(id) || AD_TOKEN.test(cls)) {
      e.stopPropagation();
      e.preventDefault();
    }
  }, true);
})();
''';

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
    // Rede de pop-ups falsos de "instale o navegador" (zona 156269). Troca de
    // domínio com frequência; o que segura de verdade é a regra do <html>
    // no script de adblock (removerForaDoBody)
    'leedbrott.com',
    'semicticken.com',
    'pistilairwash.cfd',
    'aretteauxil.qpon',
    'scotermarsoon.cyou',
    'subduepaler.cyou',
    // Google: verificação de tráfego dos anúncios e o detector de bloqueador
    // (Funding Choices), que mostra aviso quando os anúncios não carregam
    'adtrafficquality.google',
    'fundingchoicesmessages.google.com',
  ];

  /// Elementos escondidos por CSS em todos os sites: espaços de anúncio que
  /// ficam dentro da página, onde o bloqueio por domínio não alcança. Só
  /// regras genéricas (as diretrizes proíbem regra feita para um site):
  /// avisos que cobrem a página ficam com a regra de sobreposições
  /// ([getAdBlockScript], `removerSobreposicoes`).
  static const List<String> seletoresEscondidos = [
    // Blocos do Google AdSense (ex.: "Descobrir mais" e anúncios no meio)
    'ins.adsbygoogle',
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

  /// Domínios que o usuário liberou além do site do link (hoje nenhuma tela
  /// grava; é a base do futuro "adblock por site"). O app não traz nenhum:
  /// as diretrizes proíbem lista embutida de sites (docs/diretrizes-projeto.md).
  static Future<List<String>> getAllowedDomains() =>
      _readStringList(kAllowedDomains);

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

  /// Entrada com ponto casa por RÓTULOS inteiros do host ('doubleclick.net'
  /// pega 'ad.doubleclick.net', mas 'adjust.com' não pega 'cadjust.com';
  /// 'pagead2.googlesyndication' pega 'pagead2.googlesyndication.com').
  /// Entrada sem ponto é palavra-chave e casa por trecho do host.
  /// Mesma regra do `hostCasa` do script de adblock.
  static bool hostCasaComEntrada(String host, String entrada) {
    if (entrada.contains('.')) return '.$host.'.contains('.$entrada.');
    return host.contains(entrada);
  }

  /// URL de anúncio pela lista: entrada com "/" casa na URL inteira, as
  /// demais pelo host ([hostCasaComEntrada]). Quem chama deve isentar antes o
  /// site da sessão e os domínios permitidos.
  static bool urlEhAnuncio(String url, Iterable<String> entradas) {
    final s = url.toLowerCase();
    final host = originHostFromUrl(url) ?? '';
    for (final raw in entradas) {
      final e = raw.trim().toLowerCase();
      if (e.isEmpty) continue;
      if (e.contains('/')) {
        if (s.contains(e)) return true;
      } else if (host.isNotEmpty && hostCasaComEntrada(host, e)) {
        return true;
      }
    }
    return false;
  }

  static String? originHostFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return null;
    return uri.host.toLowerCase();
  }

  /// Domínio do site a partir do host do link: sem o "www." do começo, para
  /// que `www.site.com`, `site.com` e os subdomínios dele contem como o mesmo
  /// site (alguns sites trocam entre eles). Não tira o "www." quando sobraria
  /// só o sufixo (ex.: `www.com`).
  static String dominioDoSite(String host) {
    final h = host.toLowerCase();
    if (h.startsWith('www.') && h.indexOf('.', 4) > 0) return h.substring(4);
    return h;
  }

  /// A URL é do site da sessão: o domínio de [originHost] ([dominioDoSite])
  /// ou um subdomínio dele.
  static bool isSameOriginHost(String url, String originHost) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    final o = dominioDoSite(originHost);
    if (o.isEmpty) return false;
    return host == o || host.endsWith('.$o');
  }

  /// Verifica pelo HOST (não pela URL inteira), para que um domínio permitido
  /// escondido em query string / caminho não libere a navegação.
  /// - Entrada com ponto (ex.: 'site.com'): host igual ou subdomínio.
  /// - Entrada sem ponto (ex.: 'site'): aparece como trecho do host.
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

  // ---------------------------------------------------------------------------
  // COMPATIBILIDADE
  // ---------------------------------------------------------------------------
  // O navegador embutido tem marcas que alguns sites confundem com robô (sem
  // window.chrome, pontes do app, "Android WebView" nos client hints). Os
  // scripts abaixo só tiram essas marcas, para a página tratar o leitor como
  // um navegador comum; os valores do aparelho continuam os reais
  // (docs/diretrizes-projeto.md: "compatibilidade").

  /// Compatibilidade no Linux (CEF) e no iOS. Até a v2.2.1 também falseava
  /// `webdriver`, `platform`, `hardwareConcurrency` e `deviceMemory`; isso
  /// saiu por ir além de compatibilidade. Se um site voltar a recusar o
  /// leitor no Linux, confira primeiro o `navigator.webdriver` do CEF.
  static const String scriptCompatibilidade = r'''
(function() {
  if (window.__mangaCompatibilidade) return;
  window.__mangaCompatibilidade = true;

  // O Chrome de verdade tem window.chrome; o navegador embutido, não
  if (!window.chrome) {
    window.chrome = { runtime: {}, app: { isInstalled: false } };
  }
  // Idioma do usuário (o CEF vem em inglês)
  try {
    Object.defineProperty(navigator, 'languages', {
      get: function() { return ['pt-BR', 'pt', 'en-US', 'en']; },
      configurable: true
    });
  } catch (e) {}

  // Câmera e microfone recusados direto (evita pedidos de permissão)
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

  /// Compatibilidade no ANDROID (WebView do Chromium). Não mexe nos valores
  /// do aparelho (platform, languages, hardwareConcurrency, deviceMemory,
  /// webdriver): o WebView já devolve os reais, que batem com o UA de Chrome
  /// Android. Só tira as marcas de "app embutido":
  ///  - a marca "Android WebView" em navigator.userAgentData (client hints);
  ///  - as pontes window.Flutter / window.Android;
  ///  - captura de mídia (evita pedidos de permissão).
  static const String scriptCompatibilidadeAndroid = r'''
(function() {
  if (window.__mangaCompatibilidadeAndroid) return;
  window.__mangaCompatibilidadeAndroid = true;

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

  /// [sessionOriginHost] = host da URL inicial; vale o domínio do site
  /// ([dominioDoSite]) e os subdomínios dele, como no [isSameOriginHost].
  /// [adDomains] / [allowedDomains] podem ser passados para evitar reler o banco.
  /// [diagnostico]: a página guarda em `window.__mangaDiag` as requisições que
  /// falharam, os erros de JavaScript e as navegações bloqueadas, para o
  /// leitor registrar no log (ver [scriptLerDiagnostico]).
  /// [bloquearNavegacaoPorScript]: cancela pela Navigation API a navegação da
  /// página inteira para host não permitido. Só o Linux liga: o BrowserScreen
  /// já cancela pelo shouldOverrideUrlLoading. EM TESTE: suspeito de causar
  /// "Erro ao carregar o capítulo" num site ao abrir um link salvo.
  /// [bloquearElementosDeAnuncio]: recusa que a página insira `<script>` ou
  /// `<iframe>` de domínio de anúncio (o anúncio nem roda). Essencial no
  /// Linux, onde o CEF não bloqueia o download; no Windows é proteção extra.
  /// [removerForaDoBody]: remove o que a página prender direto no `<html>`,
  /// fora do `<head>` e do `<body>`. Página de verdade não põe nada ali (o
  /// leitor de HTML move para o `<body>` o que vem depois dele), mas as redes
  /// de anúncio põem: pop-ups falsos de "instale o navegador" e o anúncio fixo
  /// do Google. Não depende de domínio, então pega as redes que trocam de
  /// domínio toda semana.
  /// [removerSobreposicoes]: esconde o que cobre a página sozinho (aviso de
  /// doação ou de "desative o bloqueador", anúncio em tela cheia), por uma
  /// regra genérica, sem lista de sites. O usuário desliga por site no botão
  /// da barra do leitor ([scriptSobreposicoes]).
  ///
  /// As listas vão para o JS como JSON e a comparação é feita pelo HOST
  /// (nada de regex interpolada, então entradas com "/" não quebram o script).
  static Future<String> getAdBlockScript({
    String? sessionOriginHost,
    List<String>? adDomains,
    List<String>? allowedDomains,
    bool diagnostico = false,
    bool bloquearNavegacaoPorScript = false,
    bool bloquearElementosDeAnuncio = true,
    bool removerForaDoBody = true,
    bool removerSobreposicoes = true,
  }) async {
    final ads = adDomains ?? await getAdDomains();
    final allowed = allowedDomains ?? await getAllowedDomains();

    final allowSet = <String>{
      ...allowed.map((e) => e.trim().toLowerCase()),
      if (sessionOriginHost != null && sessionOriginHost.isNotEmpty)
        dominioDoSite(sessionOriginHost),
    }..removeWhere((e) => e.isEmpty);

    final adList = ads
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    final adJson = jsonEncode(adList);
    final allowJson = jsonEncode(allowSet.toList());
    // String JS pronta (com aspas e escapes) via JSON
    final cssEscondidosJson = jsonEncode(
      '${seletoresEscondidos.join(', ')} { display: none !important; }',
    );

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

  // Diagnóstico (só quando o leitor pede): o app lê window.__mangaDiag ao fechar
  const DIAGNOSTICO = $diagnostico;
  const BLOQUEAR_NAVEGACAO = $bloquearNavegacaoPorScript;
  const BLOQUEAR_ELEMENTOS = $bloquearElementosDeAnuncio;
  const REMOVER_FORA_DO_BODY = $removerForaDoBody;
  const REMOVER_SOBREPOSICOES = $removerSobreposicoes;
  const DIAG = DIAGNOSTICO
    ? (window.__mangaDiag = window.__mangaDiag ||
        { bloqueios: [], http: [], erros: [], elementos: [] })
    : null;
  function anotar(chave, msg) {
    if (!DIAG || !DIAG[chave] || DIAG[chave].length >= 40) return;
    DIAG[chave].push(new Date().toISOString().slice(11, 19) + ' ' + String(msg).slice(0, 300));
  }

  // Quem recusou a requisição: desafio anti-robô da Cloudflare (cabeçalho
  // cf-mitigated ou página "Just a moment") ou o próprio servidor do site
  function detalheDaFalha(cabecalho, corpo) {
    const mitigado = cabecalho('cf-mitigated');
    const desafio = mitigado || /just a moment|cf-chl|challenge-platform/i.test(corpo || '');
    return ' [server=' + (cabecalho('server') || '?') +
      (mitigado ? ', cf-mitigated=' + mitigado : '') +
      (desafio ? ', DESAFIO CLOUDFLARE' : '') +
      ', corpo=' + String(corpo || '').replace(/\\s+/g, ' ').slice(0, 80) + ']';
  }
  if (DIAG) {
    window.addEventListener('error', function(e) {
      anotar('erros', (e.message || 'erro') + ' @ ' + (e.filename || '') + ':' + (e.lineno || ''));
    });
    window.addEventListener('unhandledrejection', function(e) {
      const r = e.reason;
      anotar('erros', 'promise: ' + ((r && (r.message || String(r))) || r));
    });
  }

  function hostOf(url) {
    try { return new URL(String(url || ''), location.href).hostname.toLowerCase(); }
    catch (_) { return ''; }
  }

  // Entrada com ponto casa por RÓTULOS inteiros do host: 'doubleclick.net'
  // pega 'ad.doubleclick.net', mas 'adjust.com' não pega 'cadjust.com'.
  // Entrada sem ponto é palavra-chave (trecho do host). Mesma regra de
  // BrowserHelper.hostCasaComEntrada no Dart.
  function hostCasa(h, e) {
    if (e.indexOf('.') >= 0) return ('.' + h + '.').indexOf('.' + e + '.') >= 0;
    return h.indexOf(e) >= 0;
  }

  // Entrada com ponto: host igual ou subdomínio; sem ponto: trecho do host
  function isAllowedHost(h) {
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

  function isAllowedNav(url) {
    return isAllowedHost(hostOf(url));
  }

  // O site da sessão e os domínios permitidos NUNCA são anúncio (protege os
  // scripts e imagens do próprio site de uma entrada genérica da lista).
  // Entrada com "/" casa na URL inteira.
  function isAd(url) {
    const s = String(url || '').toLowerCase();
    const h = hostOf(s);
    if (isAllowedHost(h)) return false;
    for (let i = 0; i < AD_LIST.length; i++) {
      const e = AD_LIST[i];
      if (e.indexOf('/') >= 0) {
        if (s.indexOf(e) >= 0) return true;
      } else if (h && hostCasa(h, e)) {
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
      const resposta = _fetch.apply(this, arguments);
      if (!DIAG) return resposta;
      return resposta.then(function(r) {
        // Resposta opaca (pedido no-cors, ex.: o teste de conexão
        // gstatic.com/generate_204) sempre vem com status 0, mesmo quando deu
        // certo: não é falha
        if (r && !r.ok && r.type !== 'opaque' && r.type !== 'opaqueredirect') {
          const cab = function(n) { try { return r.headers.get(n); } catch (_) { return null; } };
          // Lê uma cópia do corpo: a resposta original segue intacta para o site
          r.clone().text().then(function(corpo) {
            anotar('http', r.status + ' ' + url + detalheDaFalha(cab, corpo));
          }, function() {
            anotar('http', r.status + ' ' + url + detalheDaFalha(cab, ''));
          });
        }
        return r;
      }, function(err) {
        anotar('http', 'falhou ' + url + ' (' + err + ')');
        throw err;
      });
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
        this.__mangaUrl = url;
        return _open.apply(this, arguments);
      };
      xhrProto.send = function() {
        if (this.__mangaBlocked) return; // Aborta silenciosamente
        if (DIAG) {
          const xhr = this;
          xhr.addEventListener('loadend', function() {
            if (xhr.status === 0 || xhr.status >= 400) {
              const cab = function(n) { try { return xhr.getResponseHeader(n); } catch (_) { return null; } };
              let corpo = '';
              try {
                if (xhr.responseType === '' || xhr.responseType === 'text') corpo = xhr.responseText;
              } catch (_) {}
              anotar('http', xhr.status + ' ' + xhr.__mangaUrl + detalheDaFalha(cab, corpo));
            }
          });
        }
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

  // Scripts e quadros de anúncio inseridos pela página: a inserção é recusada,
  // então o anúncio nem roda (o CEF do Linux não bloqueia o download).
  // Cobre o src (propriedade e setAttribute), appendChild/insertBefore/append/
  // prepend e um observador que remove o que escapar (ex.: iframe via
  // innerHTML). Script escrito direto no HTML original continua passando.
  if (BLOQUEAR_ELEMENTOS) {
    try {
      const ALVOS = { SCRIPT: true, IFRAME: true };
      const ehAlvo = function(no) {
        return !!(no && no.nodeType === 1 && ALVOS[no.tagName]);
      };
      const recusar = function(el, url) {
        anotar('elementos', String(el.tagName).toLowerCase() + ' ' + url);
      };
      const srcDeAnuncio = function(el) {
        const url = (el.getAttribute && el.getAttribute('src')) || '';
        return (url && isAd(url)) ? url : '';
      };
      // Tira os anúncios de dentro de um elemento ou fragmento
      const limparDescendentes = function(no) {
        if (!no || !no.querySelectorAll) return;
        const lista = no.querySelectorAll('script[src], iframe[src]');
        for (let i = 0; i < lista.length; i++) {
          const url = srcDeAnuncio(lista[i]);
          if (url) { recusar(lista[i], url); lista[i].remove(); }
        }
      };
      // true = o próprio nó é anúncio e não deve ser inserido
      const recusarInsercao = function(no) {
        if (!no) return false;
        if (ehAlvo(no)) {
          const url = srcDeAnuncio(no);
          if (url) { recusar(no, url); return true; }
          return false;
        }
        if (no.nodeType === 1 || no.nodeType === 11) limparDescendentes(no);
        return false;
      };

      const protegerSrc = function(proto) {
        const desc = proto && Object.getOwnPropertyDescriptor(proto, 'src');
        if (!desc || !desc.set) return;
        Object.defineProperty(proto, 'src', {
          configurable: true,
          enumerable: desc.enumerable,
          get: desc.get,
          set: function(valor) {
            if (isAd(String(valor))) { recusar(this, String(valor)); return; }
            desc.set.call(this, valor);
          }
        });
      };
      protegerSrc(window.HTMLScriptElement && HTMLScriptElement.prototype);
      protegerSrc(window.HTMLIFrameElement && HTMLIFrameElement.prototype);

      const _setAttribute = Element.prototype.setAttribute;
      Element.prototype.setAttribute = function(nome, valor) {
        if (ehAlvo(this) && String(nome).toLowerCase() === 'src' && isAd(String(valor))) {
          recusar(this, String(valor));
          return;
        }
        return _setAttribute.apply(this, arguments);
      };

      const _appendChild = Node.prototype.appendChild;
      Node.prototype.appendChild = function(no) {
        if (recusarInsercao(no)) return no;
        return _appendChild.apply(this, arguments);
      };
      const _insertBefore = Node.prototype.insertBefore;
      Node.prototype.insertBefore = function(no) {
        if (recusarInsercao(no)) return no;
        return _insertBefore.apply(this, arguments);
      };
      ['append', 'prepend'].forEach(function(metodo) {
        const original = Element.prototype[metodo];
        if (typeof original !== 'function') return;
        Element.prototype[metodo] = function() {
          const nos = [];
          for (let i = 0; i < arguments.length; i++) {
            if (!recusarInsercao(arguments[i])) nos.push(arguments[i]);
          }
          return original.apply(this, nos);
        };
      });

      new MutationObserver(function(mutacoes) {
        for (let i = 0; i < mutacoes.length; i++) {
          const adicionados = mutacoes[i].addedNodes;
          for (let j = 0; j < adicionados.length; j++) {
            const no = adicionados[j];
            if (ehAlvo(no)) {
              const url = srcDeAnuncio(no);
              if (url) { recusar(no, url); no.remove(); }
            } else if (no.nodeType === 1) {
              limparDescendentes(no);
            }
          }
        }
      }).observe(document, { childList: true, subtree: true });
    } catch (e) {
      anotar('erros', 'bloqueio de elementos desligado: ' + e);
    }
  }

  // Anúncio preso direto no <html>, fora do <head> e do <body>: pop-ups
  // falsos de "instale o navegador" vêm num div fixo com z-index 2147483646 e
  // quadros sem endereço, que o bloqueio por domínio não alcança. Observa só
  // os filhos do <html> (sem subtree), então custa quase nada.
  if (REMOVER_FORA_DO_BODY) {
    try {
      const limparRaiz = function() {
        const raiz = document.documentElement;
        if (!raiz) return;
        const filhos = raiz.children;
        for (let i = filhos.length - 1; i >= 0; i--) {
          const el = filhos[i];
          if (el.tagName === 'HEAD' || el.tagName === 'BODY') continue;
          anotar('elementos', 'fora do body: ' + el.tagName.toLowerCase() +
            (el.className ? '.' + String(el.className).split(' ')[0] : ''));
          el.remove();
        }
      };
      // O app injeta o script no começo do documento, quando o <html> ainda
      // não existe (observe(null) dá erro e desligava a regra sem aviso):
      // observa o document até o <html> aparecer, e liga a regra nele
      let raizObservada = null;
      const observarRaiz = function() {
        const raiz = document.documentElement;
        if (!raiz || raiz === raizObservada) return;
        raizObservada = raiz;
        new MutationObserver(limparRaiz).observe(raiz, { childList: true });
        limparRaiz();
      };
      new MutationObserver(observarRaiz).observe(document, { childList: true });
      observarRaiz();
    } catch (e) {
      anotar('erros', 'regra do <html> desligada: ' + e);
    }
  }

  // Espaços de anúncio dentro da página (BrowserHelper.seletoresEscondidos),
  // como os blocos do Google AdSense: escondidos por CSS. No Linux o script
  // do Google vem escrito no HTML e carrega (o CEF não bloqueia o download).
  // A folha é construída (adoptedStyleSheets), não é elemento: a regra do
  // <html> acima não a remove.
  try {
    const estilo = new CSSStyleSheet();
    estilo.replaceSync($cssEscondidosJson);
    document.adoptedStyleSheets = document.adoptedStyleSheets.concat([estilo]);
  } catch (e) {
    anotar('erros', 'CSS dos anúncios desligado: ' + e);
  }

  // Sobreposição que cobre a página sozinha (aviso de doação ou de "desative
  // o bloqueador", anúncio em tela cheia): escondida por uma regra genérica,
  // sem lista de sites. Conta como sobreposição o elemento fixo, visível e
  // clicável, por cima de tudo (z-index >= 1000), que cobre pelo menos 60% da
  // tela e apareceu sem um clique ou tecla do usuário logo antes: o menu, o
  // login e a lista de capítulos que o usuário abre ficam. O leitor em tela
  // cheia de um site também fica (conteúdo maior que a tela, imagens grandes,
  // vídeo ou canvas). Só esconde (display: none), não remove, para o site
  // seguir funcionando; e solta a trava de rolagem que o próprio aviso pôs
  // (overflow: hidden no style do <html>/<body>). O botão da barra do leitor
  // desliga a regra por site: window.__mangaSobreposicoes.ativa (ver
  // BrowserHelper.scriptSobreposicoes).
  if (REMOVER_SOBREPOSICOES && window.top === window) {
    try {
      const estado = window.__mangaSobreposicoes = window.__mangaSobreposicoes || {};
      const ativa = function() { return estado.ativa !== false; };
      const escondidos = [];
      const travas = [];
      let ultimaInteracao = 0;

      const descrever = function(el) {
        return el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') +
          (el.className && typeof el.className === 'string'
            ? '.' + el.className.trim().split(' ')[0] : '');
      };
      const ehSobreposicao = function(el) {
        if (!el || el.nodeType !== 1 || el === document.body ||
            el === document.documentElement) return false;
        const cs = getComputedStyle(el);
        if (cs.position !== 'fixed' || cs.display === 'none' ||
            cs.visibility === 'hidden' || cs.pointerEvents === 'none') return false;
        if (parseFloat(cs.opacity) < 0.1) return false;
        if (!(parseInt(cs.zIndex, 10) >= 1000)) return false;
        const vw = window.innerWidth, vh = window.innerHeight;
        const r = el.getBoundingClientRect();
        const largura = Math.min(r.right, vw) - Math.max(r.left, 0);
        const altura = Math.min(r.bottom, vh) - Math.max(r.top, 0);
        if (largura <= 0 || altura <= 0 || largura * altura < 0.6 * vw * vh) return false;
        // Leitor em tela cheia do site, não um aviso: conteúdo maior que a
        // tela, vídeo ou canvas, ou imagem alta como uma página de capítulo
        // (na tela ou no tamanho original, já que pode não ter carregado).
        // Fotos pequenas (avatares) e banners largos e baixos não contam.
        if (el.scrollHeight > vh * 1.5) return false;
        if (el.querySelector('video, canvas')) return false;
        const imagens = el.getElementsByTagName('img');
        for (let i = 0; i < imagens.length; i++) {
          const img = imagens[i];
          if (img.getBoundingClientRect().height > vh * 0.8 ||
              img.naturalHeight >= 1000 ||
              parseInt(img.getAttribute('height') || '0', 10) >= 1000) return false;
        }
        return true;
      };
      const soltarTrava = function() {
        [document.documentElement, document.body].forEach(function(el) {
          if (!el) return;
          ['overflow', 'overflow-y'].forEach(function(prop) {
            if (el.style.getPropertyValue(prop) !== 'hidden') return;
            travas.push({ el: el, prop: prop, prioridade: el.style.getPropertyPriority(prop) });
            el.style.removeProperty(prop);
          });
        });
      };
      const esconder = function(el) {
        if (el.__mangaSobreposicao) return;
        el.__mangaSobreposicao = true;
        escondidos.push({
          el: el,
          valor: el.style.getPropertyValue('display'),
          prioridade: el.style.getPropertyPriority('display'),
        });
        el.style.setProperty('display', 'none', 'important');
        anotar('elementos', 'sobreposição: ' + descrever(el));
        soltarTrava();
      };
      const restaurar = function() {
        while (escondidos.length) {
          const e = escondidos.pop();
          e.el.__mangaSobreposicao = false;
          if (e.valor) e.el.style.setProperty('display', e.valor, e.prioridade);
          else e.el.style.removeProperty('display');
        }
        while (travas.length) {
          const t = travas.pop();
          t.el.style.setProperty(t.prop, 'hidden', t.prioridade);
        }
      };

      // O que cobre a tela logo depois de um clique ou tecla foi aberto pelo
      // usuário (menu, login, lista de capítulos): fica marcado e nunca é
      // escondido, nem depois
      const conferir = function(lote) {
        if (!ativa()) return;
        const doUsuario = Date.now() - ultimaInteracao < 1500;
        lote.forEach(function(el) {
          if (!el.isConnected || el.__mangaDoUsuario || !ehSobreposicao(el)) return;
          if (doUsuario) el.__mangaDoUsuario = true;
          else esconder(el);
        });
      };
      // Até 3 níveis abaixo do <body>, onde ficam os avisos (é barato)
      const varrer = function() {
        if (!document.body) return;
        conferir(Array.from(document.body.querySelectorAll(
          'body > *, body > * > *, body > * > * > *')));
      };
      // O botão da barra liga e desliga sem recarregar a página (definido
      // antes dos observadores, para funcionar mesmo se um deles falhar)
      estado.aplicar = function() {
        if (ativa()) varrer();
        else restaurar();
      };
      ['pointerdown', 'keydown', 'touchstart'].forEach(function(tipo) {
        window.addEventListener(tipo, function() {
          ultimaInteracao = Date.now();
          // Marca o que o usuário abrir agora, inclusive com animação
          [150, 600, 1200].forEach(function(ms) { setTimeout(varrer, ms); });
        }, true);
      });

      // Elementos novos ou que mudaram (ex.: ganharam a classe que abre o
      // aviso), em lotes: confere após 150 ms e de novo após 1 s (aviso que
      // entra com animação de transparência)
      let pendentes = [];
      let agendado = false;
      const agendar = function(el) {
        if (!el || el.nodeType !== 1) return;
        pendentes.push(el);
        if (agendado) return;
        agendado = true;
        setTimeout(function() {
          agendado = false;
          const lote = pendentes;
          pendentes = [];
          conferir(lote);
          setTimeout(function() { conferir(lote); }, 1000);
        }, 150);
      };
      new MutationObserver(function(mutacoes) {
        // Enquanto o HTML carrega, a varredura do DOMContentLoaded basta
        if (!ativa() || document.readyState === 'loading') return;
        for (let i = 0; i < mutacoes.length; i++) {
          const m = mutacoes[i];
          if (m.type === 'attributes') { agendar(m.target); continue; }
          for (let j = 0; j < m.addedNodes.length; j++) agendar(m.addedNodes[j]);
        }
        // O document, não o <html>: no começo do documento, quando o app
        // injeta o script, o <html> ainda não existe
      }).observe(document, {
        childList: true, subtree: true,
        attributes: true, attributeFilter: ['class', 'style', 'open', 'hidden'],
      });
      // Depois de carregar, confere de novo por alguns segundos: avisos que
      // abrem com atraso ou entram com animação (opacidade ainda baixa na
      // primeira olhada) sem mudar o próprio elemento
      const depoisDeCarregar = function() {
        varrer();
        [1000, 3000, 6000, 12000].forEach(function(ms) { setTimeout(varrer, ms); });
      };
      document.addEventListener('DOMContentLoaded', varrer);
      if (document.readyState === 'complete') depoisDeCarregar();
      else window.addEventListener('load', depoisDeCarregar);
    } catch (e) {
      anotar('erros', 'regra de sobreposições desligada: ' + e);
    }
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

  // Pop-under que troca a página inteira por anúncio via script
  // (location.href = '...') não passa pelo clique acima. A Navigation API do
  // Chromium avisa ANTES de sair da página e permite cancelar: no Linux (CEF,
  // que não intercepta navegação) isso evita o leitor voltar recarregando o
  // capítulo. Só na janela principal; voltar/avançar e recarregar passam.
  try {
    if (BLOQUEAR_NAVEGACAO && window.top === window && window.navigation &&
        typeof window.navigation.addEventListener === 'function') {
      window.navigation.addEventListener('navigate', function(e) {
        try {
          if (!e.cancelable) return;
          if (e.navigationType === 'traverse' || e.navigationType === 'reload') return;
          const destino = (e.destination && e.destination.url) || '';
          if (!destino || /^(about|javascript|data|blob):/i.test(destino)) return;
          if (isAllowedNav(destino)) return;
          anotar('bloqueios', destino);
          e.preventDefault();
        } catch (_) {}
      });
    }
  } catch (_) {}
})();
''';
  }

  /// Liga ou desliga a regra de sobreposições do adblock na página
  /// ([getAdBlockScript], `removerSobreposicoes`). Vai como user script antes
  /// do adblock e, rodado de novo na página aberta, vale na hora: desligar
  /// mostra de volta o que tinha sido escondido.
  static String scriptSobreposicoes({required bool ativa}) =>
      '''
(function() {
  var s = window.__mangaSobreposicoes = window.__mangaSobreposicoes || {};
  s.ativa = $ativa;
  if (typeof s.aplicar === 'function') s.aplicar();
})();
''';

  // ---------------------------------------------------------------------------
  // ROLAGEM DO MOUSE (JS)
  // ---------------------------------------------------------------------------

  /// Rolagem do mouse com distância e suavidade ajustáveis (leitor desktop).
  ///
  /// Os plugins entregam ao navegador um giro da roda já multiplicado, por
  /// isso a página "pula" muito mais que num navegador comum:
  /// - flutter_inappwebview_windows 0.6.0 (`InAppWebView::sendScroll`)
  ///   multiplica por 6 o delta do Flutter (100 por giro, com 3 linhas por
  ///   giro no Windows): a página recebe 600/120 = 5 giros, ~500 px;
  /// - webview_cef 0.6.2 (`WebviewHandler::sendScrollEvent`) multiplica por
  ///   10 o delta do Flutter no Linux (53 por giro): ~530 px.
  ///
  /// [fatorBase] desfaz esse exagero (cada tela informa o do seu plugin), para
  /// que intensidade 100% fique em ~100 px por giro. Se um plugin mudar,
  /// confira os `deltas` de `rolagem` no diagnóstico da página.
  ///
  /// Rodar de novo na mesma página só troca a configuração. Não mexe em
  /// Ctrl/Shift + roda, na rolagem horizontal, no que a própria página já
  /// tratou (ex.: carrossel), na página trancada (janela de aviso aberta) nem
  /// quando nada pode rolar naquela direção: aí o navegador faz o de sempre.
  static String scriptRolagem(
    ConfigRolagem config, {
    required double fatorBase,
  }) {
    final cfg = jsonEncode({
      'ativa': config.ativa,
      'base': fatorBase,
      'intensidade': config.intensidade / 100,
      'tau': config.tauMs,
    });
    return _scriptRolagemModelo.replaceFirst('__CONFIG__', cfg);
  }

  // String "raw": o JS chega igual ao que está escrito aqui
  static const String _scriptRolagemModelo = r'''
(function() {
  var CONFIG = __CONFIG__;
  if (window.__mangaRolagem) { window.__mangaRolagem.configurar(CONFIG); return; }
  var cfg = CONFIG;

  // Deslize atual: elemento que rola, posição (com fração) e destino.
  // ultimaEscrita percebe quando outra coisa rolou o elemento.
  var alvo = null, posicao = 0, destino = 0, ultimaEscrita = 0;
  var animando = false, pedido = 0, ultimoQuadro = 0, parado = 0;
  var travados = typeof WeakSet === 'function' ? new WeakSet() : null;

  function raiz() { return document.scrollingElement || document.documentElement; }
  function maximo(el) { return Math.max(0, el.scrollHeight - el.clientHeight); }
  function overflowY(el) { return getComputedStyle(el).overflowY; }
  function temEspaco(el, dy) {
    return dy > 0 ? el.scrollTop < maximo(el) - 0.5 : el.scrollTop > 0.5;
  }

  // Elemento que rola sozinho: overflow auto/scroll e conteúdo maior que a
  // caixa. O body com o html "visible" passa a rolagem para a página.
  function rolavel(el) {
    if (el.scrollHeight <= el.clientHeight + 1) return false;
    var oy = overflowY(el);
    if (oy !== 'auto' && oy !== 'scroll' && oy !== 'overlay') return false;
    if (el === document.body && overflowY(document.documentElement) === 'visible') return false;
    return true;
  }

  // A página trancou a rolagem (ex.: janela de aviso aberta): não força
  function paginaRola() {
    var oy = overflowY(document.documentElement);
    if (oy === 'visible' && document.body) oy = overflowY(document.body);
    return oy !== 'hidden' && oy !== 'clip';
  }

  // Do elemento sob o mouse para cima, o primeiro que ainda rola nessa
  // direção (como o navegador encadeia a rolagem); senão, a página
  function acharAlvo(e, dy) {
    var r = raiz();
    if (!r) return null;
    var caminho = e.composedPath ? e.composedPath() : [];
    for (var i = 0; i < caminho.length; i++) {
      var el = caminho[i];
      if (el === r) break;
      if (!el || el.nodeType !== 1 || (travados && travados.has(el))) continue;
      if (rolavel(el) && temEspaco(el, dy)) return el;
    }
    if (travados && travados.has(r)) return null;
    return paginaRola() && temEspaco(r, dy) ? r : null;
  }

  function escrever(v) {
    try { alvo.scrollTo({ top: v, behavior: 'instant' }); }
    catch (_) { alvo.scrollTop = v; }
    ultimaEscrita = alvo.scrollTop;
  }

  function parar() {
    if (pedido) cancelAnimationFrame(pedido);
    animando = false; pedido = 0; ultimoQuadro = 0; parado = 0;
  }

  function quadro(t) {
    pedido = 0;
    if (!animando || !alvo) return;
    // Outra coisa rolou (barra de rolagem, teclado, a própria página): solta
    if (Math.abs(alvo.scrollTop - ultimaEscrita) > 3) { parar(); return; }
    var dt = ultimoQuadro ? Math.min(Math.max(t - ultimoQuadro, 0), 100) : 16;
    ultimoQuadro = t;
    var max = maximo(alvo);
    if (destino > max) destino = max;
    if (destino < 0) destino = 0;
    // Percorre uma fração do que falta, pelo tempo do quadro (suave em 60 ou 144 Hz)
    var k = cfg.tau > 0 ? 1 - Math.exp(-dt / cfg.tau) : 1;
    posicao += (destino - posicao) * k;
    if (Math.abs(destino - posicao) < 0.5) posicao = destino;
    var antes = alvo.scrollTop;
    escrever(posicao);
    // Vários quadros sem sair do lugar, longe do destino: algo impede
    // (ex.: scroll-snap). Esse elemento fica com o navegador.
    if (Math.abs(alvo.scrollTop - antes) < 0.01 && Math.abs(destino - alvo.scrollTop) > 2) {
      if (++parado >= 10) {
        if (travados) travados.add(alvo);
        parar();
        return;
      }
    } else {
      parado = 0;
    }
    if (posicao === destino) parar();
    else pedido = requestAnimationFrame(quadro);
  }

  function aoGirar(e) {
    var dy = e.deltaY;
    // Diagnóstico (só com o leitor em debug): o que o plugin entrega por giro
    var d = window.__mangaDiag, diag = null;
    if (d) {
      diag = d.rolagem || (d.rolagem = { eventos: 0, tratados: 0, deltas: [] });
      diag.eventos++;
      if (diag.deltas.length < 10) {
        diag.deltas.push(Math.round(dy) + (e.deltaMode ? '/modo' + e.deltaMode : ''));
      }
    }

    if (!cfg.ativa || e.defaultPrevented || e.ctrlKey || e.metaKey || e.shiftKey) return;
    if (!dy || Math.abs(e.deltaX) > Math.abs(dy)) return;
    // O Chromium manda em pixels; linhas e páginas só por garantia
    if (e.deltaMode === 1) dy *= 40;
    else if (e.deltaMode === 2) dy *= window.innerHeight;

    var el = acharAlvo(e, dy);
    if (!el) return;
    e.preventDefault();
    if (diag) diag.tratados++;

    // Continua o deslize se for o mesmo elemento e ninguém mais o rolou
    if (el !== alvo || Math.abs(el.scrollTop - ultimaEscrita) > 3) {
      parar();
      alvo = el;
      posicao = destino = ultimaEscrita = el.scrollTop;
    } else if (!animando) {
      destino = posicao;
    }

    var giro = dy * cfg.base;  // giro sem o exagero do plugin
    destino = Math.max(0, Math.min(maximo(el), destino + giro * cfg.intensidade));

    // Sem suavidade, ou passos pequenos e seguidos (touchpad, roda de alta
    // resolução), que já chegam suaves: aplica direto
    if (cfg.tau <= 0 || (!animando && Math.abs(giro) < 40)) {
      parar();
      posicao = destino;
      escrever(posicao);
      return;
    }
    if (!animando) {
      animando = true;
      pedido = requestAnimationFrame(quadro);
    }
  }

  window.addEventListener('wheel', aoGirar, { passive: false });
  window.__mangaRolagem = {
    configurar: function(c) { cfg = c; if (!c.ativa) parar(); }
  };
})();
''';
}
