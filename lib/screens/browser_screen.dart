import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../database/db_helper.dart';

class BrowserScreen extends StatefulWidget {
  final String initialUrl;
  final String mangaTitle;

  const BrowserScreen({
    super.key,
    required this.initialUrl,
    required this.mangaTitle,
  });

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  InAppWebViewController? webViewController;

  // bool _isWebViewReady = false;
  String? _currentUrl;

  final ValueNotifier<bool> _isLoading = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _hasError = ValueNotifier<bool>(false);
  final ValueNotifier<String> _errorMessage = ValueNotifier<String>('');

  final ValueNotifier<double> _posTop = ValueNotifier<double>(20.0);
  final ValueNotifier<double> _posLeft = ValueNotifier<double>(20.0);
  final ValueNotifier<bool> _isVertical = ValueNotifier<bool>(false);

  // Lista unificada de padrões de anúncios
  final List<String> _adPatterns = const [
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
  ];

  // Helper para verificar se uma URL contém padrões de anúncio
  bool _isAd(String url) {
    final lowerUrl = url.toLowerCase();
    for (final pattern in _adPatterns) {
      if (lowerUrl.contains(pattern)) {
        return true;
      }
    }
    return false;
  }

  // Script para interceptar requisições fetch
  final String _interceptorScript = '''
    (function() {
      const originalFetch = window.fetch;
      window.fetch = async function(...args) {
        console.log('[MangaManager Interceptor] Fetch disparado para:', args[0]);
        const response = await originalFetch.apply(this, args);
        return response;
      };
    })();
  ''';

  // Adicione no initialUserScripts ou injete no onWebViewCreated
  final String _adBlockScript = '''
(function() {
  // Bloqueia popups
  window.open = function() { return null; };

  // Impede cliques em elementos de anúncio
  document.addEventListener('click', function(e) {
    const target = e.target;
    if (!target) return;

    const id = (target.id || '').toLowerCase();
    const className = (target.className || '').toString().toLowerCase();
    const tag = target.tagName;

    if (
      tag === 'IFRAME' ||
      id.includes('ad') ||
      id.includes('ads') ||
      className.includes('ad') ||
      className.includes('ads') ||
      className.includes('popup') ||
      className.includes('banner')
    ) {
      e.stopPropagation();
      e.preventDefault();
    }
  }, true);
})();
''';

  // Script para esconder "STEALTH FORTE" que é WebView / automação
  final String _stealthScript = '''
(function() {
  // Helper para tentar redefinir sem quebrar
  function safeDefine(obj, prop, value) {
    try {
      const desc = Object.getOwnPropertyDescriptor(obj, prop) || 
                   Object.getOwnPropertyDescriptor(Object.getPrototypeOf(obj), prop);
      
      if (!desc || desc.configurable) {
        Object.defineProperty(obj, prop, {
          get: () => value,
          configurable: true
        });
      }
    } catch (e) {}
  }

  // 1. webdriver
  safeDefine(Navigator.prototype, 'webdriver', undefined);

  // 2. Chrome básico
  if (!window.chrome) {
    window.chrome = {
      runtime: {},
      app: { isInstalled: false }
    };
  }

  // 3. Languages
  safeDefine(navigator, 'languages', ['pt-BR', 'pt', 'en-US', 'en']);

  // 4. Platform (mobile realista)
  safeDefine(navigator, 'platform', 'Linux armv8l');

  // 5. Hardware
  safeDefine(navigator, 'hardwareConcurrency', 8);
  safeDefine(navigator, 'deviceMemory', 8);

  // 6. Remove sinais óbvios de Flutter
  try {
    delete window.Flutter;
    delete window.Android;
  } catch (e) {}

  // Não mexe mais em plugins (era o que gerava o erro)

  console.log('[MangaManager] Stealth suave aplicado');
})();
''';

  @override
  void initState() {
    super.initState();
    _carregarConfiguracoesBarra();
  }

  Future<void> _abrirComCustomTabs(String url) async {
    final ChromeSafariBrowser browser = ChromeSafariBrowser();

    await browser.open(
      url: WebUri(url),
      settings: ChromeSafariBrowserSettings(
        shareState: CustomTabsShareState.SHARE_STATE_OFF,
        isSingleInstance: false,
        isTrustedWebActivity: false, // importante
        keepAliveEnabled: true,
        // Cores (opcional)
        toolbarBackgroundColor: Colors.black,
        // secondaryToolbarColor: Colors.black,
      ),
    );
  }

  Future<void> _carregarConfiguracoesBarra() async {
    final db = DbHelper();
    final xStr = await db.getConfig('barra_x');
    final yStr = await db.getConfig('barra_y');
    final isVertStr = await db.getConfig('barra_vertical');

    if (xStr != null) _posLeft.value = double.tryParse(xStr) ?? 20.0;
    if (yStr != null) _posTop.value = double.tryParse(yStr) ?? 20.0;
    if (isVertStr != null) _isVertical.value = isVertStr == 'true';
  }

  Future<void> _salvarPosicaoBarra() async {
    final db = DbHelper();
    await db.setConfig('barra_x', _posLeft.value.toString());
    await db.setConfig('barra_y', _posTop.value.toString());
  }

  Future<void> _salvarOrientacaoBarra() async {
    final db = DbHelper();
    await db.setConfig('barra_vertical', _isVertical.value.toString());
  }

  @override
  void dispose() {
    _isLoading.dispose();
    _hasError.dispose();
    _errorMessage.dispose();
    _posTop.dispose();
    _posLeft.dispose();
    _isVertical.dispose();
    super.dispose();
  }

  Future<void> _voltarComUrl() async {
    if (mounted) {
      Navigator.pop(context, _currentUrl);
    }
  }

  // ========== USER AGENT REALISTA ==========
  String _obterUserAgent() {
    if (kIsWeb) {
      return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
    }

    if (Platform.isAndroid || Platform.isIOS) {
      // Mobile: UA de Android real (para passar na detecção do site)
      return 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
    }

    // Windows / Linux / macOS → UA de desktop
    return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        await _voltarComUrl();
      },
      child: Scaffold(
        body: Stack(
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: _hasError,
              builder: (context, hasError, child) {
                if (hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 50,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Falha ao carregar WebView:\n${_errorMessage.value}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
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

                return InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(widget.initialUrl)),
                  initialSettings: InAppWebViewSettings(
                    databaseEnabled: true,
                    sharedCookiesEnabled: true,
                    mediaPlaybackRequiresUserGesture: false,
                    allowsInlineMediaPlayback: true,
                    javaScriptCanOpenWindowsAutomatically: false,
                    supportMultipleWindows: false,
                    mixedContentMode:
                        MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                    useWideViewPort: true,
                    loadWithOverviewMode: true,
                    preferredContentMode: (Platform.isAndroid || Platform.isIOS)
                        ? UserPreferredContentMode.MOBILE
                        : UserPreferredContentMode.DESKTOP,
                    userAgent: _obterUserAgent(),
                    isInspectable: true,

                    // Otimizações leves
                    cacheEnabled: true,
                    clearCache: false, // não limpa toda vez
                    cacheMode: CacheMode.LOAD_DEFAULT,

                    // Reduz um pouco o trabalho de render
                    hardwareAcceleration: true,
                    useHybridComposition: true,

                    // Evita recarregamentos desnecessários
                    allowsBackForwardNavigationGestures: true,

                    // Performance
                    verticalScrollBarEnabled: false, // opcional (estética)
                    horizontalScrollBarEnabled: false,

                    // Mantém JavaScript e cookies (importante pro site)
                    javaScriptEnabled: true,
                    domStorageEnabled: true,
                    thirdPartyCookiesEnabled: true,
                    useShouldOverrideUrlLoading: true,
                    useShouldInterceptRequest: true,
                  ),
                  onWebViewCreated: (controller) async {
                    webViewController = controller;

                    // 1º - Stealth
                    // Só aplica stealth forte no mobile
                    if (Platform.isAndroid || Platform.isIOS) {
                      await controller.evaluateJavascript(
                        source: _stealthScript,
                      );
                    }

                    // 2º - AdBlock
                    await controller.evaluateJavascript(source: _adBlockScript);

                    // 3º - Interceptor
                    await controller.evaluateJavascript(
                      source: _interceptorScript,
                    );
                  },

                  onLoadStart: (controller, url) async {
                    _isLoading.value = true;
                    _hasError.value = false;

                    if (url != null) {
                      _currentUrl = url.toString();

                      // Injeta de novo (importante)
                      try {
                        await controller.evaluateJavascript(
                          source: _stealthScript,
                        );
                        await controller.evaluateJavascript(
                          source: _interceptorScript,
                        );
                      } catch (e) {
                        debugPrint(
                          '[MangaManager] Erro ao reinjetar scripts: $e',
                        );
                      }
                    }
                  },

                  onLoadStop: (controller, url) async {
                    _isLoading.value = false;

                    if (url == null) return;
                    _currentUrl = url.toString();

                    // Injeta stealth + interceptor
                    await controller.evaluateJavascript(source: _stealthScript);
                    await controller.evaluateJavascript(
                      source: _interceptorScript,
                    );

                    // Espera um pouco e verifica se o React montou
                    await Future.delayed(const Duration(seconds: 4));

                    final result = await controller.evaluateJavascript(
                      source: '''
                        (function() {
                          const root = document.getElementById('root');
                          if (!root) return false;
                          // Se tiver mais de 100 caracteres, considera que renderizou
                          return root.innerHTML.length > 100;
                        })();
                      ''',
                    );

                    final renderizou = result == true;

                    if (!renderizou && url.toString().contains('/r/')) {
                      if (Platform.isAndroid || Platform.isIOS) {
                        // abre Custom Tabs
                        await _abrirComCustomTabs(url.toString());
                      } else {
                        // no desktop só mostra erro ou tenta reload
                        debugPrint(
                          '[MangaManager] Falhou no desktop, sem Custom Tabs',
                        );
                      }
                    }
                  },

                  shouldOverrideUrlLoading:
                      (controller, navigationAction) async {
                        final url =
                            navigationAction.request.url?.toString() ?? '';

                        if (_isAd(url)) {
                          debugPrint('[MangaManager] Bloqueado (Ad): $url');
                          return NavigationActionPolicy.CANCEL;
                        }

                        if (!url.contains('nexustoons.com') &&
                            !url.contains('nx-toons.xyz')) {
                          return NavigationActionPolicy.CANCEL;
                        }
                        return NavigationActionPolicy.ALLOW;
                      },

                  shouldInterceptRequest: (controller, request) async {
                    final url = request.url.toString();

                    if (_isAd(url)) {
                      debugPrint(
                        '[MangaManager] Interceptado (bloqueado): $url',
                      );
                      try {
                        return WebResourceResponse(
                          contentType: 'text/plain',
                          data: Uint8List.fromList([]),
                          statusCode: 200,
                        );
                      } catch (e) {
                        debugPrint(
                          '[MangaManager] Erro ao criar resposta vazia: $e',
                        );
                        return null;
                      }
                    }

                    return null;
                  },

                  onCreateWindow: (controller, createWindowRequest) async {
                    return false; // impede popups / novas janelas
                  },

                  onReceivedError: (controller, request, error) {
                    final urlStr = request.url.toString();
                    if (urlStr == 'about:blank' ||
                        (request.isForMainFrame ?? false) == false) {
                      return;
                    }
                    debugPrint(
                      '[MangaManager] Erro de Recurso [${error.type}]: ${error.description}',
                    );
                    _isLoading.value = false;
                    _hasError.value = true;
                    _errorMessage.value =
                        'Tipo: ${error.type}\nMensagem: ${error.description}';
                  },
                );
              },
            ),

            ValueListenableBuilder<bool>(
              valueListenable: _isLoading,
              builder: (context, isLoading, child) {
                // if (isLoading && _isWebViewReady && !_hasError.value) {
                //    return const Center(child: CircularProgressIndicator());
                // }
                if (isLoading && !_hasError.value) {
                  return const Center(child: CircularProgressIndicator());
                }
                return const SizedBox.shrink();
              },
            ),

            ListenableBuilder(
              listenable: Listenable.merge([_posTop, _posLeft, _isVertical]),
              builder: (context, child) {
                return Positioned(
                  top: _posTop.value.clamp(0.0, screenSize.height - 60.0),
                  left: _posLeft.value.clamp(0.0, screenSize.width - 60.0),
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      _posLeft.value = (_posLeft.value + details.delta.dx)
                          .clamp(0.0, screenSize.width - 60.0);
                      _posTop.value = (_posTop.value + details.delta.dy).clamp(
                        0.0,
                        screenSize.height - 60.0,
                      );
                    },
                    onPanEnd: (details) => _salvarPosicaoBarra(),
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white24, width: 1),
                        ),
                        child: Flex(
                          direction: _isVertical.value
                              ? Axis.vertical
                              : Axis.horizontal,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back,
                                color: Colors.white,
                                size: 20,
                              ),
                              tooltip: 'Voltar',
                              onPressed: _voltarComUrl,
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.refresh,
                                color: Colors.white,
                                size: 20,
                              ),
                              tooltip: 'Recarregar',
                              onPressed: () {
                                if (_hasError.value) {
                                  _hasError.value = false;
                                  _isLoading.value = true;
                                  webViewController?.reload();
                                } else {
                                  _isLoading.value = true;
                                  webViewController?.reload();
                                }
                              },
                            ),
                            IconButton(
                              icon: Icon(
                                _isVertical.value
                                    ? Icons.view_column_outlined
                                    : Icons.view_stream_outlined,
                                color: Colors.white,
                                size: 20,
                              ),
                              tooltip: 'Alternar Orientação',
                              onPressed: () {
                                _isVertical.value = !_isVertical.value;
                                _salvarOrientacaoBarra();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
