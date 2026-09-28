import 'dart:collection';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:window_manager/window_manager.dart';

import '../database/db_helper.dart';
import '../widgets/floating_control_bar.dart';

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
  // ==========================================
  // 1. CONFIGURAÇÕES UNIFICADAS
  // ==========================================
  static const bool _isDebugMode = false;

  InAppWebViewController? webViewController;
  String? _currentUrl;

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

  // ==========================================
  // 2. OTIMIZAÇÃO DE ADBLOCK
  // ==========================================
  static final RegExp _adRegex = RegExp(
    r'(dearthsongman\.shop|officeklafter\.com|loafedspences\.com|fauldspelikeyellows\.qpon|bhatrelime|tcliktrc|acquirepopdownloadnow|doubleclick\.net|googlesyndication\.com|pagead2\.googlesyndication)',
    caseSensitive: false,
  );

  bool _isAd(String url) => _adRegex.hasMatch(url);

  // ==========================================
  // 3. SCRIPTS INTOCADOS
  // ==========================================
  final String _interceptorScript = '''
    (function() {
      const originalFetch = window.fetch;
      window.fetch = async function(...args) {
        const response = await originalFetch.apply(this, args);
        return response;
      };
    })();
  ''';

  final String _adBlockAndF11Script = '''
    (function() {
      window.open = function() { return null; };

      document.addEventListener('click', function(e) {
        const target = e.target;
        if (!target) return;

        const id = (target.id || '').toLowerCase();
        const className = (target.className || '').toString().toLowerCase();
        const tag = target.tagName;

        if (
          tag === 'IFRAME' ||
          id.includes('ad') || id.includes('ads') ||
          className.includes('ad') || className.includes('ads') ||
          className.includes('popup') || className.includes('banner')
        ) {
          e.stopPropagation();
          e.preventDefault();
        }
      }, true);

      window.addEventListener('keydown', function(e) {
        if (e.key === 'F11') {
          e.preventDefault();
          window.flutter_inappwebview.callHandler('toggleFullScreen');
        }
      });
    })();
  ''';

  final String _stealthScript = '''
    (function() {
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

      safeDefine(Navigator.prototype, 'webdriver', undefined);
      if (!window.chrome) {
        window.chrome = { runtime: {}, app: { isInstalled: false } };
      }
      safeDefine(navigator, 'languages', ['pt-BR', 'pt', 'en-US', 'en']);
      safeDefine(navigator, 'platform', 'Win32');
      safeDefine(navigator, 'hardwareConcurrency', 8);
      safeDefine(navigator, 'deviceMemory', 8);

      try {
        delete window.Flutter;
        delete window.Android;
      } catch (e) {}
    })();
  ''';

  String _obterUserAgent() {
    if (kIsWeb || _isDesktop) {
      return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
    }
    return 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
  }

  late final List<UserScript> _initialUserScripts = [
    if (Platform.isAndroid || Platform.isIOS)
      UserScript(
        source: _stealthScript,
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    UserScript(
      source: _adBlockAndF11Script,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    ),
    UserScript(
      source: _interceptorScript,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    ),
  ];

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
    _carregarConfiguracoesBarra();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    if (_isDesktop) {
      windowManager.setTitleBarStyle(TitleBarStyle.normal);
      windowManager.setFullScreen(false);
      windowManager.maximize();
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _isLoading.dispose();
    _hasError.dispose();
    _errorMessage.dispose();
    _posTop.dispose();
    _posLeft.dispose();
    _isVertical.dispose();
    super.dispose();
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
        bool isFullScreen = await windowManager.isFullScreen();
        bool novoEstado = !isFullScreen;

        if (novoEstado) {
          await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
        } else {
          await windowManager.setTitleBarStyle(TitleBarStyle.normal);
        }

        await windowManager.setFullScreen(novoEstado);
      } catch (_) {}
    } else {
      _isMobileFullScreen = !_isMobileFullScreen;
      if (_isMobileFullScreen) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }
  }

  Future<void> _abrirComCustomTabs(String url) async {
    final ChromeSafariBrowser browser = ChromeSafariBrowser();
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

  Future<void> _voltarComUrl() async {
    if (_isDesktop) {
      try {
        bool isFullScreen = await windowManager.isFullScreen();
        if (isFullScreen) {
          await windowManager.setTitleBarStyle(TitleBarStyle.normal);
          await windowManager.setFullScreen(false);
        }
      } catch (_) {}
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    if (mounted) {
      Navigator.pop(context, _currentUrl);
    }
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
        backgroundColor: Colors.black,
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
                  initialUserScripts: UnmodifiableListView(_initialUserScripts),
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
                    preferredContentMode: _isDesktop
                        ? UserPreferredContentMode.DESKTOP
                        : UserPreferredContentMode.MOBILE,
                    userAgent: _obterUserAgent(),
                    isInspectable: _isDebugMode,
                    cacheEnabled: true,
                    clearCache: _isDebugMode,
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
                  ),
                  onWebViewCreated: (controller) async {
                    webViewController = controller;

                    controller.addJavaScriptHandler(
                      handlerName: 'toggleFullScreen',
                      callback: (args) {
                        _toggleFullScreen();
                      },
                    );
                  },
                  onLoadStart: (controller, url) async {
                    _isLoading.value = true;
                    _hasError.value = false;
                    if (url != null) _currentUrl = url.toString();
                  },
                  onLoadStop: (controller, url) async {
                    _isLoading.value = false;
                    if (url == null) return;
                    _currentUrl = url.toString();

                    await Future.delayed(const Duration(seconds: 4));
                    final result = await controller.evaluateJavascript(
                      source: '''
                        (function() {
                          const root = document.getElementById('root');
                          if (!root) return false;
                          return root.innerHTML.length > 100;
                        })();
                      ''',
                    );

                    if (result != true && url.toString().contains('/r/')) {
                      if (Platform.isAndroid || Platform.isIOS) {
                        await _abrirComCustomTabs(url.toString());
                      }
                    }
                  },
                  shouldOverrideUrlLoading:
                      (controller, navigationAction) async {
                        final url =
                            navigationAction.request.url?.toString() ?? '';
                        if (_isAd(url)) {
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
                  onCreateWindow: (controller, createWindowRequest) async =>
                      false,
                  onReceivedError: (controller, request, error) {
                    if (request.url.toString() == 'about:blank' ||
                        (request.isForMainFrame ?? false) == false) {
                      return;
                    }
                    _isLoading.value = false;
                    _hasError.value = true;
                    if (_isDebugMode) {
                      _errorMessage.value =
                          'Tipo: ${error.type}\nMensagem: ${error.description}';
                    } else {
                      _errorMessage.value =
                          'Verifique sua conexão com a internet.';
                    }
                  },
                );
              },
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _isLoading,
              builder: (context, isLoading, child) {
                if (isLoading && !_hasError.value) {
                  return const Center(child: CircularProgressIndicator());
                }
                return const SizedBox.shrink();
              },
            ),
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
    );
  }
}
