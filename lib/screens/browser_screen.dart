import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform, Directory;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';
import 'package:path_provider/path_provider.dart';

import '../database/db_helper.dart';
import '../utils/browser_helper.dart';
import '../widgets/floating_control_bar.dart';

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

class _BrowserScreenState extends State<BrowserScreen> {
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
  String? _currentUrl;
  String? _lastAllowedUrl;

  int? _detectedChapter;
  String? _pageTitle;

  late final String _originHost;
  List<String> _allowedExtra = BrowserHelper.defaultAllowedDomains;
  RegExp? _adHostRegex; // entradas sem "/": comparadas só com o host
  RegExp? _adUrlRegex; // entradas com "/": comparadas com a URL inteira
  String _userAgent = '';
  List<UserScript> _initialUserScripts = const [];
  bool _bootstrapReady = false;

  // ValueNotifiers para estado reativo sem reconstruir a tela inteira
  final ValueNotifier<bool> _isLoading = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _hasError = ValueNotifier<bool>(false);
  final ValueNotifier<String> _errorMessage = ValueNotifier<String>('');

  final ValueNotifier<double> _posTop = ValueNotifier<double>(20.0);
  final ValueNotifier<double> _posLeft = ValueNotifier<double>(20.0);
  final ValueNotifier<bool> _isVertical = ValueNotifier<bool>(false);

  bool _isMobileFullScreen = false;

  bool get _isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS;
  }

  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  // Identidade nova só vale no Android (iOS/Linux continuam como antes)
  bool get _useAndroidV2 => _stealthMobileV2 && _isAndroid;

  @override
  void initState() {
    super.initState();
    _originHost = BrowserHelper.originHostFromUrl(widget.initialUrl) ?? '';
    _lastAllowedUrl = widget.initialUrl;
    _userAgent = _fallbackUserAgent();

    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
    _bootstrap();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    if (_isDesktop) {
      unawaited(_restaurarJanela());
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    // Libera os recursos dos Notifiers
    _isLoading.dispose();
    _hasError.dispose();
    _errorMessage.dispose();
    _posTop.dispose();
    _posLeft.dispose();
    _isVertical.dispose();

    super.dispose();
  }

  // Futures sem await dentro de um try síncrono não têm os erros capturados,
  // então a restauração da janela fica numa função própria.
  Future<void> _restaurarJanela() async {
    try {
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      await windowManager.setFullScreen(false);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // BOOTSTRAP (cada etapa falha isoladamente, sem derrubar o adblock)
  // ---------------------------------------------------------------------------

  Future<void> _bootstrap() async {
    // Posição/orientação da barra antes de mostrar a tela (evita "pulo")
    await _carregarConfiguracoesBarra();

    // 1) Ambiente do WebView (Windows) e user agent
    try {
      if (_isDesktop && Platform.isWindows) {
        await _prepararWebViewEnvironmentWindows();
        _userAgent = _fallbackUserAgent();
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
      if (_isDebugMode) {
        debugPrint('[BrowserScreen] Falha no ambiente/UA: $e\n$st');
      }
      _userAgent = _fallbackUserAgent();
    }

    // 2) Listas de domínios
    var adDomains = List<String>.from(BrowserHelper.defaultAdDomains);
    try {
      _allowedExtra = await BrowserHelper.getAllowedDomains();
      adDomains = await BrowserHelper.getAdDomains();
    } catch (e, st) {
      if (_isDebugMode) {
        debugPrint('[BrowserScreen] Falha ao ler listas de domínios: $e\n$st');
      }
    }
    _compilarRegexAnuncios(adDomains);

    // 3) Script de adblock (listas passadas por parâmetro: sem reler o banco)
    String adJs = '';
    try {
      adJs = await BrowserHelper.getAdBlockScript(
        sessionOriginHost: _originHost,
        adDomains: adDomains,
        allowedDomains: _allowedExtra,
      );
    } catch (e, st) {
      if (_isDebugMode) {
        debugPrint('[BrowserScreen] Falha ao montar o adblock: $e\n$st');
      }
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
      // Clique agressivo apenas para Desktop/Windows
      if (_isDesktop)
        UserScript(
          source: _aggressiveClickScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
    ];

    if (mounted) {
      setState(() => _bootstrapReady = true);
      WidgetsBinding.instance.addPostFrameCallback((_) => _clampPosicaoBarra());
    }
  }

  Future<void> _prepararWebViewEnvironmentWindows() async {
    if (_sharedWebViewEnvironment == null) {
      final versao = await WebViewEnvironment.getAvailableVersion();
      if (versao == null) {
        _errorMessage.value =
            'WebView2 Runtime não encontrado. Instale o Microsoft Edge WebView2 Runtime e tente novamente.';
        _hasError.value = true;
        _isLoading.value = false;
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
      if (_isDebugMode) {
        debugPrint('[BrowserScreen] Falha ao ler UA padrão do WebView: $e');
      }
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

  void _applyChapterFromText(String? text) {
    final ch = BrowserHelper.parseChapter(
      title: text,
      url: _lastAllowedUrl ?? _currentUrl,
    );
    if (ch != null) {
      _detectedChapter = ch;
      if (_isDebugMode) {
        debugPrint(
          '[BrowserScreen] Capítulo detectado: $ch | texto original: $text | title: $_pageTitle',
        );
      }
    }
  }

  // Anúncio: compara só o HOST (ex.: 'adjust.com' não pega mais query string
  // nem caminho); entradas com "/" continuam comparando a URL inteira.
  bool _isAd(String url) {
    if (url.isEmpty) return false;
    final host = BrowserHelper.originHostFromUrl(url);
    if (host != null && (_adHostRegex?.hasMatch(host) ?? false)) return true;
    return _adUrlRegex?.hasMatch(url) ?? false;
  }

  // Permitida: compara o HOST (um domínio permitido escondido na query string
  // não libera mais a navegação).
  bool _isAllowedUrl(String url) {
    if (url.isEmpty || url.startsWith('about:') || url.startsWith('data:')) {
      return false;
    }
    if (_originHost.isNotEmpty &&
        BrowserHelper.isSameOriginHost(url, _originHost)) {
      return true;
    }
    return BrowserHelper.hostMatchesAllowed(url, _allowedExtra);
  }

  String _fallbackUserAgent() {
    if (kIsWeb || _isDesktop) {
      return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
    }
    return 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
  }

  bool _handleGlobalKey(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f11) {
      _toggleFullScreen();
      return true;
    }
    return false;
  }

  Future<void> _toggleFullScreen() async {
    if (_isDesktop) {
      try {
        final isFullScreen = await windowManager.isFullScreen();
        final novoEstado = !isFullScreen;
        await windowManager.setTitleBarStyle(
          novoEstado ? TitleBarStyle.hidden : TitleBarStyle.normal,
        );
        await windowManager.setFullScreen(novoEstado);
      } catch (e) {
        if (_isDebugMode) {
          debugPrint('[BrowserScreen] Erro FullScreen Desktop: $e');
        }
      }
    } else {
      _isMobileFullScreen = !_isMobileFullScreen;
      SystemChrome.setEnabledSystemUIMode(
        _isMobileFullScreen
            ? SystemUiMode.immersiveSticky
            : SystemUiMode.edgeToEdge,
      );
    }
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
      if (_isDebugMode) debugPrint('[BrowserScreen] Erro CustomTabs: $e');
    }
  }

  Future<void> _carregarConfiguracoesBarra() async {
    try {
      final db = DbHelper();
      final xStr = await db.getConfig('barra_x');
      final yStr = await db.getConfig('barra_y');
      final isVertStr = await db.getConfig('barra_vertical');

      if (xStr != null) _posLeft.value = double.tryParse(xStr) ?? 20.0;
      if (yStr != null) _posTop.value = double.tryParse(yStr) ?? 20.0;
      if (isVertStr != null) _isVertical.value = isVertStr == 'true';
    } catch (e) {
      if (_isDebugMode) {
        debugPrint('[BrowserScreen] Erro ao carregar config da barra: $e');
      }
    }
  }

  // Garante que a barra não abra fora da tela (janela menor, zoom diferente...)
  void _clampPosicaoBarra() {
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    const double minVisivel = 48;

    final maxLeft = (size.width - minVisivel).clamp(0.0, double.infinity);
    final maxTop = (size.height - minVisivel).clamp(0.0, double.infinity);

    _posLeft.value = _posLeft.value.clamp(0.0, maxLeft).toDouble();
    _posTop.value = _posTop.value.clamp(0.0, maxTop).toDouble();
  }

  Future<void> _salvarPosicaoBarra() async {
    try {
      final db = DbHelper();
      // Uma casa decimal basta (antes salvava 31.33333333333313)
      await db.setConfig('barra_x', _posLeft.value.toStringAsFixed(1));
      await db.setConfig('barra_y', _posTop.value.toStringAsFixed(1));
    } catch (e) {
      if (_isDebugMode) {
        debugPrint('[BrowserScreen] Erro ao salvar posição da barra: $e');
      }
    }
  }

  Future<void> _salvarOrientacaoBarra() async {
    try {
      await DbHelper().setConfig(
        'barra_vertical',
        _isVertical.value.toString(),
      );
    } catch (e) {
      if (_isDebugMode) {
        debugPrint('[BrowserScreen] Erro ao salvar orientação da barra: $e');
      }
    }
  }

  Future<void> _voltarComUrl() async {
    if (_isDesktop) {
      try {
        if (await windowManager.isFullScreen()) {
          await windowManager.setTitleBarStyle(TitleBarStyle.normal);
          await windowManager.setFullScreen(false);
        }
      } catch (_) {}
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    if (mounted) {
      Navigator.pop(context, {
        'url': _lastAllowedUrl ?? _currentUrl ?? widget.initialUrl,
        'capitulo': _detectedChapter,
      });
    }
  }

  Future<void> _tryDetectChapter(InAppWebViewController controller) async {
    try {
      final t = await controller.getTitle();
      _pageTitle = t;
      _applyChapterFromText(t);
    } catch (_) {}

    if (_detectedChapter != null) return;

    try {
      final raw = await controller.evaluateJavascript(
        source: r'''
        (function() {
          var h = document.querySelector('h1, h2, header, [class*="title"], [class*="chapter"]');
          if (!h) return document.title || '';
          return (h.innerText || h.textContent || '').slice(0, 200);
        })();
      ''',
      );
      if (raw != null) {
        _applyChapterFromText(raw.toString());
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        await _voltarComUrl();
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
                  valueListenable: _hasError,
                  builder: (context, hasError, child) {
                    if (hasError) {
                      return _buildErrorState();
                    }
                    return _buildWebView();
                  },
                ),

              ValueListenableBuilder<bool>(
                valueListenable: _isLoading,
                builder: (context, isLoading, child) {
                  if (isLoading && !_hasError.value && _bootstrapReady) {
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
                FloatingControlBar(
                  posTop: _posTop,
                  posLeft: _posLeft,
                  isVertical: _isVertical,
                  screenSize: screenSize,
                  onPanEnd: _salvarPosicaoBarra,
                  onBack: _voltarComUrl,
                  onReload: () {
                    if (_hasError.value) _hasError.value = false;
                    _isLoading.value = true;
                    webViewController?.reload();
                  },
                  onFullScreen: _toggleFullScreen,
                  onToggleOrientation: () {
                    _isVertical.value = !_isVertical.value;
                    _salvarOrientacaoBarra();
                  },
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
              _errorMessage.value,
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
              onPressed: () {
                _hasError.value = false;
                _isLoading.value = true;
                webViewController?.reload();
              },
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
        preferredContentMode: _isDesktop
            ? UserPreferredContentMode.DESKTOP
            : UserPreferredContentMode.MOBILE,
        userAgent: _userAgent,
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
          callback: (args) => _toggleFullScreen(),
        );
      },
      onTitleChanged: (controller, title) {
        _pageTitle = title;
        if (_isDebugMode) {
          debugPrint('[BrowserScreen] title: $title');
        }
        _applyChapterFromText(title);
      },
      onLoadStart: (controller, url) async {
        final u = url?.toString() ?? '';
        if (_isAllowedUrl(u)) {
          _isLoading.value = true;
          _hasError.value = false;
          _currentUrl = u;
          _lastAllowedUrl = u;
        }
      },
      onLoadStop: (controller, url) async {
        final u = url?.toString() ?? '';

        if (_isAllowedUrl(u)) {
          _isLoading.value = false;
          _currentUrl = u;
          _lastAllowedUrl = u;

          final chUrl = BrowserHelper.parseChapterFromUrl(u);
          if (chUrl != null) _detectedChapter = chUrl;

          // title / header (uma única chamada por carregamento)
          await _tryDetectChapter(controller);
        } else if (!(u.isEmpty || u.startsWith('about:'))) {
          _isLoading.value = false;
        }

        // SPA Nexus: tratamento mobile
        if (_isAllowedUrl(u) && u.contains('/r/') && _isMobile) {
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
          if (real != null && _isAllowedUrl(real)) {
            _currentUrl = real;
            _lastAllowedUrl = real;
          }
        } catch (_) {}
      },
      onUpdateVisitedHistory: (controller, url, isReload) {
        final u = url?.toString() ?? '';
        if (u.isEmpty) return;
        if (_isAllowedUrl(u)) {
          _currentUrl = u;
          _lastAllowedUrl = u;
          final ch = BrowserHelper.parseChapterFromUrl(u);
          if (ch != null) _detectedChapter = ch;
        }
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
        if (_isAllowedUrl(url)) {
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
        if (!_isAllowedUrl(u) && u.isNotEmpty) return;

        // Mensagem antes do flag: a tela de erro lê o texto ao reconstruir
        _errorMessage.value = _isDebugMode
            ? 'Tipo: ${error.type}\nMensagem: ${error.description}'
            : 'Verifique sua conexão com a internet ou se o site está online.';

        _isLoading.value = false;
        _hasError.value = true;
      },
    );
  }

  // SCRIPTS ESTÁTICOS
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

  // Casa "ad", "ads", "banner"... só como palavra inteira na classe/id
  // (antes, 'ad' pegava "read", "reader", "header", "loader", "download"...)
  static const String _aggressiveClickScript = r'''
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
