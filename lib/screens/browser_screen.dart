import 'dart:collection';
import 'dart:io' show Platform;
// import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:window_manager/window_manager.dart';

import '../database/db_helper.dart';
import '../utils/browser_helper.dart';
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
  static const bool _isDebugMode = false;

  InAppWebViewController? webViewController;
  String? _currentUrl;
  String? _lastAllowedUrl;

  late final String _originHost;
  List<String> _allowedExtra = BrowserHelper.defaultAllowedDomains;
  RegExp? _adRegex;
  String _userAgent = '';
  List<UserScript> _initialUserScripts = const [];
  bool _bootstrapReady = false;

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

  bool _isAd(String url) {
    if (url.isEmpty) return false;
    return _adRegex?.hasMatch(url) ?? false;
  }

  /// Origem da sessão (host de initialUrl) + extras do helper/DB.
  bool _isAllowedUrl(String url) {
    if (url.isEmpty || url.startsWith('about:') || url.startsWith('data:')) {
      return false;
    }
    if (_originHost.isNotEmpty &&
        BrowserHelper.isSameOriginHost(url, _originHost)) {
      return true;
    }
    final lower = url.toLowerCase();
    return _allowedExtra.any((d) => lower.contains(d.toLowerCase()));
  }

  String _fallbackUserAgent() {
    if (kIsWeb || _isDesktop) {
      return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
    }
    return 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
  }

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

  static const String _aggressiveClickScript = r'''
(function() {
  if (window.__mangaAggressiveClick) return;
  window.__mangaAggressiveClick = true;
  document.addEventListener('click', function(e) {
    const target = e.target;
    if (!target) return;
    const id = (target.id || '').toLowerCase();
    const className = (target.className || '').toString().toLowerCase();
    const tag = (target.tagName || '').toUpperCase();
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
})();
''';

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

  @override
  void initState() {
    super.initState();
    _originHost = BrowserHelper.originHostFromUrl(widget.initialUrl) ?? '';
    _lastAllowedUrl = widget.initialUrl;
    _userAgent = _fallbackUserAgent();

    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
    _carregarConfiguracoesBarra();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      // UA: no Windows desktop prefira fallback Win; senão DB ou fallback.
      if (_isDesktop && Platform.isWindows) {
        _userAgent = _fallbackUserAgent();
      } else {
        final saved = await BrowserHelper.getUserAgent();
        if (saved.isNotEmpty && saved != BrowserHelper.defaultUserAgentLinux) {
          _userAgent = saved;
        } else {
          _userAgent = _fallbackUserAgent();
        }
      }

      _allowedExtra = await BrowserHelper.getAllowedDomains();
      final adDomains = await BrowserHelper.getAdDomains();
      _adRegex = RegExp(
        '(${adDomains.map(RegExp.escape).join('|')})',
        caseSensitive: false,
      );

      final adJs = await BrowserHelper.getAdBlockScript(
        sessionOriginHost: _originHost,
      );

      _initialUserScripts = [
        if (Platform.isAndroid || Platform.isIOS)
          UserScript(
            source: BrowserHelper.stealthScript,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          ),
        UserScript(
          source: adJs,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
        UserScript(
          source: adJs,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
        ),
        UserScript(
          source: _f11Script,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
        UserScript(
          source: _aggressiveClickScript,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
        UserScript(
          source:
              BrowserHelper.stealthScript, // base (webdriver, chrome, media…)
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
        UserScript(
          source: _mobileStealthExtra,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ];
    } catch (e, st) {
      debugPrint('[BrowserScreen] bootstrap: $e\n$st');
      _initialUserScripts = [
        UserScript(
          source: _f11Script,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        ),
      ];
    }
    if (mounted) setState(() => _bootstrapReady = true);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    if (_isDesktop) {
      try {
        windowManager.setTitleBarStyle(TitleBarStyle.normal);
        windowManager.setFullScreen(false);
        // sem maximize() forçado
      } catch (_) {}
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
        final isFullScreen = await windowManager.isFullScreen();
        final novoEstado = !isFullScreen;
        await windowManager.setTitleBarStyle(
          novoEstado ? TitleBarStyle.hidden : TitleBarStyle.normal,
        );
        await windowManager.setFullScreen(novoEstado);
      } catch (_) {}
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
    await DbHelper().setConfig('barra_vertical', _isVertical.value.toString());
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
      Navigator.pop(
        context,
        _lastAllowedUrl ?? _currentUrl ?? widget.initialUrl,
      );
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
            if (!_bootstrapReady)
              const Center(child: CircularProgressIndicator())
            else
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
                    initialUrlRequest: URLRequest(
                      url: WebUri(widget.initialUrl),
                    ),
                    initialUserScripts: UnmodifiableListView(
                      _initialUserScripts,
                    ),
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
                    ),
                    onWebViewCreated: (controller) {
                      webViewController = controller;
                      controller.addJavaScriptHandler(
                        handlerName: 'toggleFullScreen',
                        callback: (args) => _toggleFullScreen(),
                      );
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
                      } else if (!(u.isEmpty || u.startsWith('about:'))) {
                        _isLoading.value = false;
                      }

                      if (!_isAllowedUrl(u) || !u.contains('/r/')) return;

                      await Future.delayed(const Duration(seconds: 4));
                      if (!mounted) return;
                      final result = await controller.evaluateJavascript(
                        source: '''
                          (function() {
                            const root = document.getElementById('root');
                            if (!root) return false;
                            return root.innerHTML.length > 100;
                          })();
                        ''',
                      );
                      if (result != true &&
                          (Platform.isAndroid || Platform.isIOS)) {
                        await _abrirComCustomTabs(u);
                      }
                    },
                    shouldOverrideUrlLoading:
                        (controller, navigationAction) async {
                          final url =
                              navigationAction.request.url?.toString() ?? '';
                          final isMain = navigationAction.isForMainFrame;

                          if (_isAd(url)) {
                            return NavigationActionPolicy.CANCEL;
                          }
                          if (!isMain) {
                            return NavigationActionPolicy.ALLOW;
                          }
                          // Origem da sessão (qualquer site) + extras do helper
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
                    onCreateWindow: (controller, createWindowRequest) async =>
                        false,
                    onReceivedError: (controller, request, error) {
                      final u = request.url.toString();
                      if (u == 'about:blank' ||
                          request.isForMainFrame == false) {
                        return;
                      }
                      if (!_isAllowedUrl(u) && u.isNotEmpty) return;

                      _isLoading.value = false;
                      _hasError.value = true;
                      _errorMessage.value = _isDebugMode
                          ? 'Tipo: ${error.type}\nMensagem: ${error.description}'
                          : 'Verifique sua conexão com a internet.';
                    },
                  );
                },
              ),
            ValueListenableBuilder<bool>(
              valueListenable: _isLoading,
              builder: (context, isLoading, child) {
                if (isLoading && !_hasError.value && _bootstrapReady) {
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
