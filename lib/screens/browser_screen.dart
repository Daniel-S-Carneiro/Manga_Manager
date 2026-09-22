import 'dart:collection';
import 'dart:io' show Platform, Process;
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

  // Novas variáveis para controle de dependências no Linux
  final ValueNotifier<bool> _isCheckingLinuxDeps = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _missingLinuxDeps = ValueNotifier<bool>(false);

  final ValueNotifier<double> _posTop = ValueNotifier<double>(20.0);
  final ValueNotifier<double> _posLeft = ValueNotifier<double>(20.0);
  final ValueNotifier<bool> _isVertical = ValueNotifier<bool>(false);

  bool _isMobileFullScreen = false;

  bool get _isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
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
      safeDefine(navigator, 'platform', 'Linux x86_64');
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
      return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';
    }
    return 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';
  }

  late final List<UserScript> _initialUserScripts = [
    if (Platform.isAndroid || Platform.isIOS || Platform.isLinux)
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

    if (!kIsWeb && Platform.isLinux) {
      _verificarDependenciasLinux();
    }
  }

  // ==========================================
  // VALIDAÇÃO DE DEPENDÊNCIAS DO LINUX
  // ==========================================
  Future<void> _verificarDependenciasLinux() async {
    _isCheckingLinuxDeps.value = true;
    try {
      final result = await Process.run('ldconfig', ['-p']);
      if (result.exitCode == 0) {
        final stdout = result.stdout.toString();
        // Checa se as bibliotecas essenciais WebKitGTK estão instaladas
        final hasWebKit =
            stdout.contains('libwebkit2gtk-4.0') ||
            stdout.contains('libwebkit2gtk-4.1');

        if (!hasWebKit) {
          _missingLinuxDeps.value = true;
        }
      }
    } catch (_) {
      // Caso o ldconfig falhe ou não exista, deixamos carregar normalmente
    } finally {
      _isCheckingLinuxDeps.value = false;
    }
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
    _isCheckingLinuxDeps.dispose();
    _missingLinuxDeps.dispose();
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

        if (!novoEstado) {
          await windowManager.maximize();
        }
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
          await windowManager.maximize();
        }
      } catch (_) {}
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    if (mounted) {
      Navigator.pop(context, _currentUrl);
    }
  }

  Widget _buildLinuxMissingDepsWidget() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 550),
        padding: const EdgeInsets.all(24.0),
        margin: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.orange.shade700, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 32,
                ),
                SizedBox(width: 12),
                Text(
                  'Dependência ausente no Linux',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'O navegador interno requer a biblioteca WebKitGTK para funcionar nesta distribuição Linux.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            const Text(
              'Execute um dos comandos abaixo no seu terminal:',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 10),
            _buildCodeSnippet(
              'Ubuntu / Debian / Mint:',
              'sudo apt install libwebkit2gtk-4.0-37',
            ),
            const SizedBox(height: 8),
            _buildCodeSnippet('Fedora:', 'sudo dnf install webkit2gtk3'),
            const SizedBox(height: 8),
            _buildCodeSnippet('Arch Linux:', 'sudo pacman -S webkit2gtk'),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _voltarComUrl,
                  child: const Text(
                    'Voltar',
                    style: TextStyle(color: Colors.white60),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    _verificarDependenciasLinux();
                  },
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Verificar Novamente'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeSnippet(String distro, String command) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(distro, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        const SizedBox(height: 2),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              SelectableText(
                command,
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: command));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Comando copiado!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: const Icon(Icons.copy, color: Colors.white54, size: 16),
              ),
            ],
          ),
        ),
      ],
    );
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
              valueListenable: _missingLinuxDeps,
              builder: (context, missingDeps, child) {
                if (missingDeps) {
                  return _buildLinuxMissingDepsWidget();
                }

                return ValueListenableBuilder<bool>(
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
                );
              },
            ),
            ValueListenableBuilder<bool>(
              valueListenable: _isLoading,
              builder: (context, isLoading, child) {
                if (isLoading && !_hasError.value && !_missingLinuxDeps.value) {
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
