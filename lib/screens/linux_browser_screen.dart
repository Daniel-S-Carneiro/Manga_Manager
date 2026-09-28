import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_cef/webview_cef.dart';
import 'package:window_manager/window_manager.dart';

import '../database/db_helper.dart';
import '../widgets/floating_control_bar.dart';

class LinuxBrowserScreen extends StatefulWidget {
  final String initialUrl;
  final String mangaTitle;

  const LinuxBrowserScreen({
    super.key,
    required this.initialUrl,
    required this.mangaTitle,
  });

  @override
  State<LinuxBrowserScreen> createState() => _LinuxBrowserScreenState();
}

class _LinuxBrowserScreenState extends State<LinuxBrowserScreen> {
  late final WebViewController _webViewController;
  bool _isReady = false;
  String? _currentUrl;
  Timer? _loadTimeout;

  final ValueNotifier<bool> _isLoading = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _hasError = ValueNotifier<bool>(false);
  final ValueNotifier<String> _errorMessage = ValueNotifier<String>('');

  final ValueNotifier<double> _posTop = ValueNotifier<double>(20.0);
  final ValueNotifier<double> _posLeft = ValueNotifier<double>(20.0);
  final ValueNotifier<bool> _isVertical = ValueNotifier<bool>(false);

  // ==========================================
  // Scripts de mitigação (adblock + stealth + domínio)
  // ==========================================

  /// Bloqueia popups, ads (fetch/XHR/DOM), cliques em anúncios e navegação
  /// para fora dos domínios permitidos. Roda cedo (LOAD_START) e de novo no LOAD_END.
  final String _adBlockScript = '''
(function() {
  if (window.__mangaAdBlockInstalled) return;
  window.__mangaAdBlockInstalled = true;

  window.open = function() { return null; };

  const AD_RE = /(dearthsongman\\.shop|officeklafter\\.com|loafedspences\\.com|fauldspelikeyellows\\.qpon|bhatrelime|tcliktrc|acquirepopdownloadnow|doubleclick\\.net|googlesyndication\\.com|pagead2\\.googlesyndication)/i;
  const ALLOWED = /(nexustoons\\.com|nx-toons\\.xyz)/i;

  function isAd(url) {
    try { return AD_RE.test(String(url || '')); } catch (_) { return false; }
  }
  function isAllowedNav(url) {
    try { return ALLOWED.test(String(url || '')); } catch (_) { return false; }
  }

  // Interceptar fetch
  const _fetch = window.fetch;
  window.fetch = function(input, init) {
    const url = (typeof input === 'string') ? input : (input && input.url);
    if (isAd(url)) return Promise.reject(new Error('blocked'));
    return _fetch.apply(this, arguments);
  };

  // Interceptar XHR
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

  // Bloquear sendBeacon de ads
  if (navigator.sendBeacon) {
    const _beacon = navigator.sendBeacon.bind(navigator);
    navigator.sendBeacon = function(url, data) {
      if (isAd(url)) return false;
      return _beacon(url, data);
    };
  }

  // Cliques: ads e links para fora do domínio
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
      return;
    }

    let el = target;
    while (el && el.tagName !== 'A') el = el.parentElement;
    if (el && el.href && !isAllowedNav(el.href)) {
      e.preventDefault();
      e.stopPropagation();
    }
  }, true);

  // Remover nodes de ad do DOM (SPA / late inject)
  const killAds = function() {
    try {
      document.querySelectorAll(
        'iframe, [id*="ad" i], [class*="ad" i], [class*="ads" i], [class*="banner" i], [class*="popup" i]'
      ).forEach(function(n) {
        try { n.remove(); } catch (_) {}
      });
    } catch (_) {}
  };
  killAds();
  try {
    new MutationObserver(killAds).observe(document.documentElement, {
      childList: true,
      subtree: true
    });
  } catch (_) {}
})();
''';

  /// Reduz detecção de automação (sites que checam webdriver / chrome / platform).
  final String _stealthScript = '''
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
  try { safeDefine(navigator, 'platform', 'Win32'); } catch (e) {}
  try { safeDefine(navigator, 'hardwareConcurrency', 8); } catch (e) {}
  try { safeDefine(navigator, 'deviceMemory', 8); } catch (e) {}
})();
''';

  static const String _desktopUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  bool _isAllowedUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('nexustoons.com') || lower.contains('nx-toons.xyz');
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
    _carregarConfiguracoesBarra();

    final scripts = InjectUserScripts()
      ..add(UserScript(_stealthScript, ScriptInjectTime.LOAD_START))
      ..add(UserScript(_adBlockScript, ScriptInjectTime.LOAD_START))
      ..add(UserScript(_adBlockScript, ScriptInjectTime.LOAD_END));

    _webViewController = WebviewManager().createWebView(
      loading: const Center(child: CircularProgressIndicator()),
      injectUserScripts: scripts,
    );

    _initCef();
  }

  Future<void> _initCef() async {
    await WebviewManager().initialize(userAgent: _desktopUserAgent);

    _webViewController.setWebviewListener(
      WebviewEventsListener(
        onUrlChanged: (url) {
          _currentUrl = url;

          // Rede de segurança: se saiu do domínio permitido, volta
          if (url.isNotEmpty &&
              !url.startsWith('about:') &&
              !_isAllowedUrl(url)) {
            _webViewController.loadUrl(widget.initialUrl);
          }
        },
        onLoadStart: (controller, url) {
          _isLoading.value = true;
          _hasError.value = false;
          _loadTimeout?.cancel();
          _loadTimeout = Timer(const Duration(seconds: 25), () {
            if (_isLoading.value) {
              _isLoading.value = false;
              _hasError.value = true;
              _errorMessage.value =
                  'Tempo esgotado. Verifique a conexão com a internet.';
            }
          });
        },
        onLoadEnd: (controller, url) {
          _loadTimeout?.cancel();
          _isLoading.value = false;
          if (url.isNotEmpty) _currentUrl = url;

          // Reforço pós-load (SPA / scripts tardios)
          _webViewController.executeJavaScript(_adBlockScript);
          _webViewController.executeJavaScript(_stealthScript);

          // Fallback leve: se /r/ não montou o root, marca erro amigável
          _checkSpaRoot(url);
        },
      ),
    );

    await _webViewController.initialize(widget.initialUrl);

    if (mounted) {
      setState(() {
        _isReady = true;
      });
    }
  }

  Future<void> _checkSpaRoot(String url) async {
    if (!url.contains('/r/')) return;
    try {
      await Future.delayed(const Duration(seconds: 4));
      if (!mounted) return;

      final result = await _webViewController.evaluateJavascript('''
        (function() {
          const root = document.getElementById('root');
          if (!root) return false;
          return root.innerHTML.length > 100;
        })();
      ''');

      // evaluateJavascript pode retornar string "true"/"false" ou bool
      final ok = result == true || result == 'true';
      if (!ok && mounted && !_hasError.value) {
        // Sem Custom Tabs no Linux: só sinaliza; usuário pode dar reload
        // ou você pode integrar url_launcher aqui se quiser abrir no browser.
        debugPrint(
          '[LinuxBrowser] SPA /r/ parece vazia após 4s — considere reload ou browser externo',
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _loadTimeout?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    windowManager.setTitleBarStyle(TitleBarStyle.normal);
    windowManager.setFullScreen(false);
    windowManager.maximize();

    _webViewController.dispose();
    // Não chame WebviewManager().quit() aqui se a app ainda for usar webviews.

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
    try {
      final isFullScreen = await windowManager.isFullScreen();
      final novoEstado = !isFullScreen;

      if (novoEstado) {
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
      } else {
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      }

      await windowManager.setFullScreen(novoEstado);
    } catch (_) {}
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
    try {
      final isFullScreen = await windowManager.isFullScreen();
      if (isFullScreen) {
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
        await windowManager.setFullScreen(false);
      }
    } catch (_) {}

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
            if (_isReady && !_hasError.value) _webViewController.webviewWidget,

            // Tela de erro (timeout / falha)
            ValueListenableBuilder<bool>(
              valueListenable: _hasError,
              builder: (context, hasError, child) {
                if (!hasError) return const SizedBox.shrink();
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
                        ValueListenableBuilder<String>(
                          valueListenable: _errorMessage,
                          builder: (context, msg, _) {
                            return Text(
                              msg.isEmpty ? 'Falha ao carregar a página.' : msg,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.red),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: () {
                            _hasError.value = false;
                            _isLoading.value = true;
                            _webViewController.reload();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tentar Novamente'),
                        ),
                      ],
                    ),
                  ),
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
                _webViewController.reload();
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
