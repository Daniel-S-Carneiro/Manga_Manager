import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_cef/webview_cef.dart';
import 'package:window_manager/window_manager.dart';

import '../database/db_helper.dart';
import '../utils/browser_helper.dart';
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
  WebViewController? _webViewController;
  bool _isReady = false;
  bool _initStarted = false;
  bool _redirecting = false;

  String? _currentUrl;
  String? _lastAllowedUrl;
  String _adBlockScriptCache = '';
  List<String> _allowedDomains = BrowserHelper.defaultAllowedDomains;
  late final String _originHost;

  Timer? _loadTimeout;

  final ValueNotifier<bool> _isLoading = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _hasError = ValueNotifier<bool>(false);
  final ValueNotifier<String> _errorMessage = ValueNotifier<String>('');

  final ValueNotifier<double> _posTop = ValueNotifier<double>(20.0);
  final ValueNotifier<double> _posLeft = ValueNotifier<double>(20.0);
  final ValueNotifier<bool> _isVertical = ValueNotifier<bool>(false);

  static const bool _kDebugLinuxBrowser = true;

  void _log(String message, [Object? detail]) {
    if (!_kDebugLinuxBrowser) return;
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    if (detail != null) {
      debugPrint('[LinuxBrowser][$ts] $message | $detail');
    } else {
      debugPrint('[LinuxBrowser][$ts] $message');
    }
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
    return _allowedDomains.any((d) => lower.contains(d.toLowerCase()));
  }

  @override
  void initState() {
    super.initState();
    _originHost = BrowserHelper.originHostFromUrl(widget.initialUrl) ?? '';
    _lastAllowedUrl = widget.initialUrl;

    _log('initState', {
      'mangaTitle': widget.mangaTitle,
      'initialUrl': widget.initialUrl,
      'originHost': _originHost,
    });

    HardwareKeyboard.instance.addHandler(_handleGlobalKey);
    _carregarConfiguracoesBarra();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _log('postFrameCallback → _initializeWebview');
      _initializeWebview();
    });
  }

  Future<void> _initializeWebview() async {
    if (_initStarted) {
      _log('_initializeWebview ignorado (já iniciado)');
      return;
    }
    _initStarted = true;

    try {
      final userAgent = await BrowserHelper.getUserAgent();
      _adBlockScriptCache = await BrowserHelper.getAdBlockScript(
        sessionOriginHost: _originHost,
      );
      _allowedDomains = await BrowserHelper.getAllowedDomains();
      final stealth = BrowserHelper.stealthScript;

      _log('config', {
        'userAgent': userAgent,
        'originHost': _originHost,
        'allowedDomains': _allowedDomains,
        'adBlockScriptLen': _adBlockScriptCache.length,
      });

      final scripts = InjectUserScripts()
        ..add(UserScript(stealth, ScriptInjectTime.LOAD_START))
        ..add(UserScript(_adBlockScriptCache, ScriptInjectTime.LOAD_START))
        ..add(UserScript(_adBlockScriptCache, ScriptInjectTime.LOAD_END));

      final controller = WebviewManager().createWebView(
        loading: const Center(child: CircularProgressIndicator()),
        injectUserScripts: scripts,
      );
      _webViewController = controller;

      _log('WebviewManager.initialize()');
      await WebviewManager().initialize(userAgent: userAgent);
      _log('WebviewManager.initialize() OK');

      controller.setWebviewListener(
        WebviewEventsListener(
          onTitleChanged: (title) {
            _log('EVENT onTitleChanged', title);
          },
          onUrlChanged: (url) {
            final allowed = _isAllowedUrl(url);
            _log('EVENT onUrlChanged', {
              'url': url,
              'allowed': allowed,
              'originHost': _originHost,
              'lastAllowed': _lastAllowedUrl,
              'redirecting': _redirecting,
            });

            if (allowed) {
              _currentUrl = url;
              _lastAllowedUrl = url;
              return;
            }

            if (url.isEmpty || url.startsWith('about:')) {
              _log('URL intermediária ignorada', url);
              return;
            }

            final backTo = _lastAllowedUrl ?? widget.initialUrl;
            if (_redirecting || backTo == url) {
              _log('redirect ignorado', {
                'redirecting': _redirecting,
                'backTo': backTo,
              });
              return;
            }

            _log('BLOQUEANDO main-frame ad → voltando', {
              'from': url,
              'to': backTo,
            });
            _redirecting = true;
            controller.loadUrl(backTo).whenComplete(() {
              _redirecting = false;
              _log('redirect concluído');
            });
          },
          onLoadStart: (c, url) {
            _log('EVENT onLoadStart', url);
            if (_redirecting) return;

            // Só timer/loading para documento da origem (evita falso "sem internet")
            if (url.isEmpty ||
                url.startsWith('about:') ||
                url.startsWith('data:') ||
                !_isAllowedUrl(url)) {
              return;
            }

            _isLoading.value = true;
            _hasError.value = false;
            _loadTimeout?.cancel();
            _loadTimeout = Timer(const Duration(seconds: 25), () {
              _log('TIMEOUT 25s');
              if (!_isLoading.value) return;
              final last = _lastAllowedUrl;
              if (last != null && _isAllowedUrl(last)) {
                _isLoading.value = false;
                return;
              }
              _isLoading.value = false;
              _hasError.value = true;
              _errorMessage.value =
                  'Tempo esgotado. Verifique a conexão com a internet.';
            });
          },
          onLoadEnd: (c, url) {
            _log('EVENT onLoadEnd', url);

            if (_isAllowedUrl(url)) {
              _loadTimeout?.cancel();
              _isLoading.value = false;
              _hasError.value = false;
              _currentUrl = url;
              _lastAllowedUrl = url;
            }

            final ad = _adBlockScriptCache;
            if (ad.isNotEmpty) {
              c
                  .executeJavaScript(ad)
                  .then((_) {
                    _log('adBlock inject OK');
                  })
                  .catchError((e) {
                    _log('adBlock inject ERRO', e);
                  });
            }
            c
                .executeJavaScript(BrowserHelper.stealthScript)
                .then((_) {
                  _log('stealth inject OK');
                })
                .catchError((e) {
                  _log('stealth inject ERRO', e);
                });

            _checkSpaRoot(url);
          },
          onConsoleMessage: (level, message, source, line) {
            _log('EVENT onConsoleMessage', {
              'level': level,
              'message': message,
              'source': source,
              'line': line,
            });
          },
        ),
      );

      _log('controller.initialize()', widget.initialUrl);
      await controller.initialize(widget.initialUrl);
      _log('controller.initialize() OK');

      if (mounted) {
        setState(() => _isReady = true);
        _log('setState _isReady=true');
      }
    } catch (e, st) {
      _log('FALHA init', e);
      debugPrint(st.toString());
      if (mounted) {
        _hasError.value = true;
        _errorMessage.value = 'Falha ao iniciar WebView: $e';
        _isLoading.value = false;
      }
    }
  }

  Future<void> _checkSpaRoot(String url) async {
    if (!url.contains('/r/')) {
      _log('_checkSpaRoot skip');
      return;
    }
    final c = _webViewController;
    if (c == null) return;
    try {
      _log('_checkSpaRoot aguardando 4s...');
      await Future.delayed(const Duration(seconds: 4));
      if (!mounted) return;
      final result = await c.evaluateJavascript('''
        (function() {
          const root = document.getElementById('root');
          if (!root) return false;
          return root.innerHTML.length > 100;
        })();
      ''');
      final ok = result == true || result == 'true';
      _log('_checkSpaRoot result', {'raw': result, 'ok': ok});
    } catch (e) {
      _log('_checkSpaRoot ERRO', e);
    }
  }

  @override
  void dispose() {
    _log('dispose', {
      'currentUrl': _currentUrl,
      'lastAllowed': _lastAllowedUrl,
    });
    _loadTimeout?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleGlobalKey);
    try {
      windowManager.setTitleBarStyle(TitleBarStyle.normal);
      windowManager.setFullScreen(false);
    } catch (_) {}
    _webViewController?.dispose();
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
      _log('KEY F11');
      _toggleFullScreen();
      return true;
    }
    return false;
  }

  Future<void> _toggleFullScreen() async {
    _log('toggleFullScreen');
    try {
      final isFull = await windowManager.isFullScreen();
      final next = !isFull;
      await windowManager.setTitleBarStyle(
        next ? TitleBarStyle.hidden : TitleBarStyle.normal,
      );
      await windowManager.setFullScreen(next);
    } catch (e) {
      _log('fullscreen ERRO', e);
    }
  }

  Future<void> _carregarConfiguracoesBarra() async {
    final db = DbHelper();
    final xStr = await db.getConfig('barra_x');
    final yStr = await db.getConfig('barra_y');
    final isVertStr = await db.getConfig('barra_vertical');
    if (xStr != null) _posLeft.value = double.tryParse(xStr) ?? 20.0;
    if (yStr != null) _posTop.value = double.tryParse(yStr) ?? 20.0;
    if (isVertStr != null) _isVertical.value = isVertStr == 'true';
    _log('barra config', {
      'left': _posLeft.value,
      'top': _posTop.value,
      'vertical': _isVertical.value,
    });
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
    _log('onBack', {'lastAllowed': _lastAllowedUrl, 'current': _currentUrl});
    try {
      if (await windowManager.isFullScreen()) {
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
        await windowManager.setFullScreen(false);
      }
    } catch (_) {}
    if (mounted) {
      final result = _lastAllowedUrl ?? _currentUrl ?? widget.initialUrl;
      _log('Navigator.pop', result);
      Navigator.pop(context, result);
    }
  }

  void _onReload() {
    _log('onReload');
    final c = _webViewController;
    if (c == null) return;
    if (_hasError.value) _hasError.value = false;
    _isLoading.value = true;
    c.reload();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final controller = _webViewController;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        _log('PopScope', {'didPop': didPop});
        if (didPop) return;
        await _voltarComUrl();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (_isReady && !_hasError.value && controller != null)
              controller.webviewWidget,

            ValueListenableBuilder<bool>(
              valueListenable: _hasError,
              builder: (context, hasError, _) {
                if (!hasError) return const SizedBox.shrink();
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
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
                          builder: (_, msg, _) => Text(
                            msg.isEmpty ? 'Falha ao carregar a página.' : msg,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _onReload,
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
              builder: (_, isLoading, _) {
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
              onBack: () {
                _log('UI onBack');
                _voltarComUrl();
              },
              onReload: () {
                _log('UI onReload');
                _onReload();
              },
              onFullScreen: () {
                _log('UI onFullScreen');
                _toggleFullScreen();
              },
              onToggleOrientation: () {
                _log('UI onToggleOrientation');
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
