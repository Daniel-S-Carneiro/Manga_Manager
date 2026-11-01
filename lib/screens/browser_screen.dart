import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform, Directory;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/browser_helper.dart';
import 'leitor_base.dart';

/// Leitor com flutter_inappwebview (Windows/WebView2, Android, iOS, macOS).
/// O comportamento comum aos leitores fica em [LeitorBase].
class BrowserScreen extends StatefulWidget {
  final String initialUrl;
  final String mangaTitle;
  final int? mangaId;

  const BrowserScreen({
    super.key,
    required this.initialUrl,
    required this.mangaTitle,
    this.mangaId,
  });

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen>
    with LeitorBase<BrowserScreen> {
  // Mantido true de propósito: interruptor manual de debug (inspeção + logs).
  static const bool _isDebugMode = true;

  // --- Interruptores dos ajustes novos --------------------------------------
  // Identidade coerente no Android (UA de Chrome com a versão real do WebView,
  // sem falsear platform, sem "Android WebView" nos client hints e sem o header
  // X-Requested-With). Se o site voltar a desconfiar, ponha false para voltar
  // exatamente ao comportamento anterior.
  static const bool _stealthMobileV2 = true;

  // Injeta o adblock também dentro de iframes (anúncios/pop-unders que nascem
  // em iframe). Se algum player ou captcha quebrar, ponha false.
  static const bool _adblockEmSubframes = true;

  // Um único ambiente WebView2 para o app todo (Windows)
  static WebViewEnvironment? _sharedWebViewEnvironment;
  WebViewEnvironment? _webViewEnvironment;

  InAppWebViewController? webViewController;

  RegExp? _adHostRegex; // entradas sem "/": comparadas só com o host
  RegExp? _adUrlRegex; // entradas com "/": comparadas com a URL inteira
  String _userAgent = '';
  List<UserScript> _initialUserScripts = const [];
  bool _bootstrapReady = false;

  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  // Identidade nova só vale no Android (iOS/Linux continuam como antes)
  bool get _useAndroidV2 => _stealthMobileV2 && _isAndroid;

  @override
  String get urlInicial => widget.initialUrl;

  @override
  void logLeitor(String mensagem) {
    if (_isDebugMode) debugPrint('[BrowserScreen] $mensagem');
  }

  @override
  void initState() {
    super.initState();
    iniciarLeitor();
    _userAgent = _fallbackUserAgent();
    _bootstrap();
  }

  @override
  void dispose() {
    encerrarLeitor();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // BOOTSTRAP (cada etapa falha isoladamente, sem derrubar o adblock)
  // ---------------------------------------------------------------------------

  Future<void> _bootstrap() async {
    // Posição/orientação da barra antes de mostrar a tela (evita "pulo")
    await carregarConfiguracoesBarra();

    // 1) Ambiente do WebView (Windows) e user agent
    try {
      if (leitorDesktop && Platform.isWindows) {
        await _prepararWebViewEnvironmentWindows();
        // Vazio = user agent do próprio WebView2 (Edge). Um UA fixo de outra
        // versão contradiz os client hints (sec-ch-ua) e a proteção anti-robô
        // dos sites desconfia: o Nexus passou a responder 503.
        _userAgent = '';
      } else if (_useAndroidV2) {
        _userAgent = await _resolverUserAgentAndroid();
      } else {
        final saved = await BrowserHelper.getUserAgent();
        if (saved.isNotEmpty && saved != BrowserHelper.defaultUserAgentLinux) {
          _userAgent = saved;
        } else {
          _userAgent = _fallbackUserAgent();
        }
      }
    } catch (e, st) {
      logLeitor('Falha no ambiente/UA: $e\n$st');
      _userAgent = (leitorDesktop && Platform.isWindows)
          ? ''
          : _fallbackUserAgent();
    }

    // 2) Listas de domínios
    var adDomains = List<String>.from(BrowserHelper.defaultAdDomains);
    try {
      allowedDomains = await BrowserHelper.getAllowedDomains();
      adDomains = await BrowserHelper.getAdDomains();
    } catch (e, st) {
      logLeitor('Falha ao ler listas de domínios: $e\n$st');
    }
    _compilarRegexAnuncios(adDomains);

    // 3) Script de adblock (listas passadas por parâmetro: sem reler o banco)
    String adJs = '';
    try {
      adJs = await BrowserHelper.getAdBlockScript(
        sessionOriginHost: originHost,
        adDomains: adDomains,
        allowedDomains: allowedDomains,
        // Com o debug ligado, a página anota falhas para o log ao fechar
        diagnostico: _isDebugMode,
      );
    } catch (e, st) {
      logLeitor('Falha ao montar o adblock: $e\n$st');
    }

    _initialUserScripts = [
      if (_isMobile)
        if (_useAndroidV2)
          UserScript(
            source: BrowserHelper.stealthScriptAndroid,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          )
        else ...[
          UserScript(
            source: BrowserHelper.stealthScript,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
          UserScript(
            source: _mobileStealthExtra,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
        ],
      // Uma única injeção (a guarda __mangaAdBlockInstalled tornava a cópia
      // em AT_DOCUMENT_END inútil)
      if (adJs.isNotEmpty)
        UserScript(
          source: adJs,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: !_adblockEmSubframes,
        ),
      UserScript(
        source: _f11Script,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
      // Clique agressivo apenas para Desktop
      if (leitorDesktop)
        UserScript(
          source: BrowserHelper.cliqueAgressivoScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
    ];

    if (mounted) {
      setState(() => _bootstrapReady = true);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => limitarPosicaoBarra(),
      );
    }
  }

  Future<void> _prepararWebViewEnvironmentWindows() async {
    if (_sharedWebViewEnvironment == null) {
      final versao = await WebViewEnvironment.getAvailableVersion();
      if (versao == null) {
        errorMessage.value =
            'WebView2 Runtime não encontrado. Instale o Microsoft Edge WebView2 Runtime e tente novamente.';
        hasError.value = true;
        isLoading.value = false;
        return;
      }

      // Pasta permitida para os dados do Edge/WebView2
      final appDir = await getApplicationSupportDirectory();
      final webViewDataDir = Directory(p.join(appDir.path, 'WebView2_Data'));
      if (!await webViewDataDir.exists()) {
        await webViewDataDir.create(recursive: true);
      }

      _sharedWebViewEnvironment = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
          userDataFolder: webViewDataDir.path,
        ),
      );
    }
    _webViewEnvironment = _sharedWebViewEnvironment;
  }

  // UA de Chrome para Android com a MESMA versão do WebView instalado, para
  // não divergir dos client hints (navigator.userAgentData / Sec-CH-UA).
  // Formato "reduzido" que o Chrome real usa (Android 10; K).
  Future<String> _resolverUserAgentAndroid() async {
    // UA salvo só vale se for de Android (o do sync remoto é Linux desktop)
    final custom = await BrowserHelper.getCustomUserAgent();
    if (custom != null && custom.contains('Android')) return custom;

    try {
      final base = await InAppWebViewController.getDefaultUserAgent();
      final major = RegExp(r'Chrome/(\d+)').firstMatch(base)?.group(1);
      if (major != null) {
        return 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$major.0.0.0 Mobile Safari/537.36';
      }
    } catch (e) {
      logLeitor('Falha ao ler UA padrão do WebView: $e');
    }
    return _fallbackUserAgent();
  }

  void _compilarRegexAnuncios(List<String> adDomains) {
    final hostEntries = <String>[];
    final urlEntries = <String>[];

    for (final raw in adDomains) {
      final e = raw.trim().toLowerCase();
      if (e.isEmpty) continue;
      (e.contains('/') ? urlEntries : hostEntries).add(RegExp.escape(e));
    }

    _adHostRegex = hostEntries.isEmpty
        ? null
        : RegExp(hostEntries.join('|'), caseSensitive: false);
    _adUrlRegex = urlEntries.isEmpty
        ? null
        : RegExp(urlEntries.join('|'), caseSensitive: false);
  }

  // Anúncio: compara só o HOST (ex.: 'adjust.com' não pega mais query string
  // nem caminho); entradas com "/" continuam comparando a URL inteira.
  bool _isAd(String url) {
    if (url.isEmpty) return false;
    final host = BrowserHelper.originHostFromUrl(url);
    if (host != null && (_adHostRegex?.hasMatch(host) ?? false)) return true;
    return _adUrlRegex?.hasMatch(url) ?? false;
  }

  String _fallbackUserAgent() {
    if (kIsWeb || leitorDesktop) {
      return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
    }
    return 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
  }

  Future<void> _abrirComCustomTabs(String url) async {
    try {
      final browser = ChromeSafariBrowser();
      await browser.open(
        url: WebUri(url),
        settings: ChromeSafariBrowserSettings(
          shareState: CustomTabsShareState.SHARE_STATE_OFF,
          isSingleInstance: false,
          isTrustedWebActivity: false,
          keepAliveEnabled: true,
          toolbarBackgroundColor: Colors.black,
        ),
      );
    } catch (e) {
      logLeitor('Erro CustomTabs: $e');
    }
  }

  // Título da aba primeiro; se não trouxer o capítulo, o cabeçalho da página
  Future<void> _tryDetectChapter(InAppWebViewController controller) async {
    try {
      pageTitle = await controller.getTitle();
    } catch (_) {}
    await detectarCapituloDaPagina(
      (script) => controller.evaluateJavascript(source: script),
    );
  }

  // Registra o que a página anotou (requisições com erro, erros de JS e
  // navegações bloqueadas): é como investigamos falhas como "Erro ao carregar"
  @override
  Future<void> antesDeFechar() async {
    final c = webViewController;
    if (!_isDebugMode || c == null) return;
    try {
      final diag = await c
          .evaluateJavascript(source: BrowserHelper.scriptLerDiagnostico)
          .timeout(const Duration(seconds: 2));
      logLeitor('diagnóstico da página: $diag');
    } catch (e) {
      logLeitor('diagnóstico indisponível: $e');
    }
  }

  void _recarregar() {
    if (hasError.value) hasError.value = false;
    isLoading.value = true;
    webViewController?.reload();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        await voltarComResultado();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              if (!_bootstrapReady)
                const Center(
                  child: CircularProgressIndicator(color: Colors.blueAccent),
                )
              else
                ValueListenableBuilder<bool>(
                  valueListenable: hasError,
                  builder: (context, erro, child) {
                    if (erro) {
                      return _buildErrorState();
                    }
                    return _buildWebView();
                  },
                ),

              ValueListenableBuilder<bool>(
                valueListenable: isLoading,
                builder: (context, carregando, child) {
                  if (carregando && !hasError.value && _bootstrapReady) {
                    return Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: const LinearProgressIndicator(
                        color: Colors.blueAccent,
                        backgroundColor: Colors.transparent,
                        minHeight: 3,
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),

              if (_bootstrapReady)
                barraDeControle(
                  tamanhoTela: screenSize,
                  onRecarregar: _recarregar,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              color: Colors.redAccent,
              size: 64,
            ),
            const SizedBox(height: 16),
            const Text(
              'Falha ao carregar a página',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage.value,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              onPressed: _recarregar,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar Novamente'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebView() {
    return InAppWebView(
      webViewEnvironment: _webViewEnvironment,
      initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
      initialUserScripts: UnmodifiableListView(_initialUserScripts),
      initialSettings: InAppWebViewSettings(
        databaseEnabled: true,
        sharedCookiesEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: false,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        useWideViewPort: true,
        loadWithOverviewMode: true,
        preferredContentMode: leitorDesktop
            ? UserPreferredContentMode.DESKTOP
            : UserPreferredContentMode.MOBILE,
        // null = user agent padrão do motor (no Windows, o do WebView2)
        userAgent: _userAgent.isEmpty ? null : _userAgent,
        isInspectable: _isDebugMode,
        cacheEnabled: true,
        clearCache: false,
        cacheMode: CacheMode.LOAD_DEFAULT,
        hardwareAcceleration: true,
        useHybridComposition: true,
        allowsBackForwardNavigationGestures: true,
        verticalScrollBarEnabled: false,
        horizontalScrollBarEnabled: false,
        javaScriptEnabled: true,
        domStorageEnabled: true,
        thirdPartyCookiesEnabled: true,
        useShouldOverrideUrlLoading: true,
        useShouldInterceptRequest: true,
        transparentBackground: true, // Evita flashs brancos ao carregar
        // Lista vazia = nenhum site recebe o header X-Requested-With (que traz
        // o nome do pacote do app). Só Android; ignorado nas demais plataformas.
        requestedWithHeaderOriginAllowList: _useAndroidV2 ? <String>{} : null,
      ),
      onWebViewCreated: (controller) {
        webViewController = controller;
        controller.addJavaScriptHandler(
          handlerName: 'toggleFullScreen',
          callback: (args) => alternarTelaCheia(),
        );
      },
      onTitleChanged: (controller, title) {
        pageTitle = title;
        logLeitor('title: $title');
        aplicarCapituloDoTexto(title);
      },
      onLoadStart: (controller, url) async {
        if (registrarUrl(url?.toString() ?? '')) {
          isLoading.value = true;
          hasError.value = false;
        }
      },
      onLoadStop: (controller, url) async {
        final u = url?.toString() ?? '';

        if (registrarUrl(u)) {
          isLoading.value = false;
          // title / header (uma única chamada por carregamento)
          await _tryDetectChapter(controller);
        } else if (!(u.isEmpty || u.startsWith('about:'))) {
          isLoading.value = false;
        }

        // SPA Nexus: tratamento mobile
        if (urlPermitida(u) && u.contains('/r/') && _isMobile) {
          await Future.delayed(const Duration(seconds: 4));
          if (!mounted) return;

          try {
            final result = await controller.evaluateJavascript(
              source: '''
                (function() {
                  const root = document.getElementById('root');
                  if (!root) return false;
                  return root.innerHTML.length > 100;
                })();
              ''',
            );
            if (result != true) {
              await _abrirComCustomTabs(u);
            }
          } catch (_) {}
        }

        // Corrige URL real em caso de redirecionamentos internos invisíveis
        try {
          final real = (await controller.getUrl())?.toString();
          if (real != null) registrarUrl(real);
        } catch (_) {}
      },
      onUpdateVisitedHistory: (controller, url, isReload) {
        registrarUrl(url?.toString() ?? '');
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final url = navigationAction.request.url?.toString() ?? '';
        final isMain = navigationAction.isForMainFrame;

        if (_isAd(url)) {
          return NavigationActionPolicy.CANCEL;
        }
        if (!isMain) {
          return NavigationActionPolicy.ALLOW;
        }
        if (urlPermitida(url)) {
          return NavigationActionPolicy.ALLOW;
        }
        return NavigationActionPolicy.CANCEL;
      },
      shouldInterceptRequest: (controller, request) async {
        final url = request.url.toString();
        if (_isAd(url)) {
          try {
            return WebResourceResponse(
              contentType: 'text/plain',
              data: Uint8List.fromList([]),
              statusCode: 200,
            );
          } catch (_) {
            return null;
          }
        }
        return null;
      },
      onCreateWindow: (controller, createWindowRequest) async => false,
      onReceivedError: (controller, request, error) {
        final u = request.url.toString();

        // Ignora about:blank e frames secundários que não renderizam página principal
        if (u == 'about:blank' || request.isForMainFrame == false) {
          return;
        }

        // Se a url não for permitida, ignora também (pode ser o adblock cancelando requisições)
        if (!urlPermitida(u) && u.isNotEmpty) return;

        // Mensagem antes do flag: a tela de erro lê o texto ao reconstruir
        errorMessage.value = _isDebugMode
            ? 'Tipo: ${error.type}\nMensagem: ${error.description}'
            : 'Verifique sua conexão com a internet ou se o site está online.';

        isLoading.value = false;
        hasError.value = true;
      },
    );
  }

  // SCRIPTS ESTÁTICOS (específicos do flutter_inappwebview)
  static const String _f11Script = r'''
(function() {
  if (window.__mangaF11Installed) return;
  window.__mangaF11Installed = true;
  window.addEventListener('keydown', function(e) {
    if (e.key === 'F11') {
      e.preventDefault();
      try {
        window.flutter_inappwebview.callHandler('toggleFullScreen');
      } catch (err) {}
    }
  });
})();
''';

  // Comportamento anterior do mobile (usado com _stealthMobileV2 = false e no iOS)
  static const String _mobileStealthExtra = r'''
(function() {
  if (window.__mangaMobileStealthExtra) return;
  window.__mangaMobileStealthExtra = true;
  try {
    Object.defineProperty(navigator, 'platform', {
      get: function() { return 'Win32'; },
      configurable: true
    });
  } catch (e) {}
  try { delete window.Flutter; } catch (e) {}
  try { delete window.Android; } catch (e) {}
})();
''';
}
