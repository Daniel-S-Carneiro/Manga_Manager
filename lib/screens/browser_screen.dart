import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

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
  WebViewEnvironment? _webViewEnvironment;
  bool _hasError = false;
  String _errorMessage = '';
  bool _isLoading = true;

  final FocusNode _focusNode = FocusNode();

  double _posTop = 20.0;
  double _posLeft = 20.0;

  @override
  void initState() {
    super.initState();

    if (_isDesktop) {
      _initWebViewEnvironment();
    }

    if (!kIsWeb && io.Platform.isLinux) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Aviso para usuários Linux'),
            content: const Text(
              'Para que o leitor de mangás funcione corretamente no Linux, certifique-se de que a biblioteca WebKitGTK (libwebkit2gtk) está instalada no seu sistema operacional.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendi'),
              ),
            ],
          ),
        );
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  Future<void> _initWebViewEnvironment() async {
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final env = await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
          userDataFolder: '${appSupportDir.path}/webViewData',
        ),
      );
      if (mounted) {
        setState(() {
          _webViewEnvironment = env;
        });
      }
    } catch (_) {}
  }

  bool get _isDesktop {
    if (kIsWeb) return false;
    return io.Platform.isWindows || io.Platform.isLinux || io.Platform.isMacOS;
  }

  @override
  void dispose() {
    if (_isDesktop) {
      windowManager.setFullScreen(false);
      windowManager.maximize();
    }
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _toggleFullScreen() async {
    if (!_isDesktop) return;

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
  }

  Future<void> _voltarComUrl() async {
    String? currentUrl;
    try {
      final uri = await webViewController?.getUrl();
      currentUrl = uri?.toString();
    } catch (_) {}

    if (mounted) {
      Navigator.pop(context, currentUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isDesktop && _webViewEnvironment == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.f11): () {
            _toggleFullScreen();
          },
        },
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (bool didPop, Object? result) async {
            if (didPop) return;
            await _voltarComUrl();
          },
          child: Scaffold(
            body: _hasError
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.orange,
                            size: 60,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'O site bloqueou ou recusou a conexão',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _errorMessage,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _voltarComUrl,
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('Voltar aos Mangás'),
                          ),
                        ],
                      ),
                    ),
                  )
                : Stack(
                    children: [
                      InAppWebView(
                        webViewEnvironment: _webViewEnvironment,
                        initialUrlRequest: URLRequest(
                          url: WebUri(widget.initialUrl),
                        ),
                        initialSettings: InAppWebViewSettings(
                          javaScriptEnabled: true,
                          useShouldOverrideUrlLoading: true,
                          mediaPlaybackRequiresUserGesture: false,
                          mixedContentMode:
                              MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                          supportMultipleWindows: true,
                        ),
                        initialUserScripts: UnmodifiableListView<UserScript>([
                          UserScript(
                            source: """
                              window.open = function() { return null; };

                              document.addEventListener('click', function(event) {
                                let target = event.target;
                                if (target && (target.tagName === 'IFRAME' || target.getAttribute('id')?.includes('ads') || target.getAttribute('class')?.includes('popup'))) {
                                  event.stopPropagation();
                                }
                              }, true);
                            """,
                            injectionTime:
                                UserScriptInjectionTime.AT_DOCUMENT_START,
                          ),
                        ]),
                        onWebViewCreated: (controller) {
                          webViewController = controller;
                        },
                        onConsoleMessage: (controller, consoleMessage) {},
                        onLoadStart: (controller, url) {
                          setState(() {
                            _isLoading = true;
                            _hasError = false;
                          });
                        },
                        onLoadStop: (controller, url) async {
                          if (mounted) {
                            setState(() => _isLoading = false);
                          }
                        },
                        onReceivedError: (controller, request, error) {
                          if (request.url.toString() == 'about:blank') return;
                          if (request.isForMainFrame != true) return;

                          if (mounted) {
                            setState(() {
                              _isLoading = false;
                              _hasError = true;
                              _errorMessage = 'Descrição: ${error.description}';
                            });
                          }
                        },
                        onCreateWindow: (controller, windowRequest) async =>
                            false,
                        shouldOverrideUrlLoading:
                            (controller, navigationAction) async {
                              final uri = navigationAction.request.url;
                              if (uri == null) {
                                return NavigationActionPolicy.CANCEL;
                              }
                              final urlStr = uri.toString();
                              if (urlStr == 'about:blank') {
                                return NavigationActionPolicy.ALLOW;
                              }

                              final initialHost = Uri.parse(
                                widget.initialUrl,
                              ).host.toLowerCase();
                              final currentHost = uri.host.toLowerCase();

                              if (currentHost.contains(initialHost) ||
                                  initialHost.contains(currentHost)) {
                                return NavigationActionPolicy.ALLOW;
                              }

                              if (urlStr.contains('bhatrelime') ||
                                  urlStr.contains('tcliktrc') ||
                                  urlStr.contains('acquirepopdownloadnow')) {
                                return NavigationActionPolicy.CANCEL;
                              }
                              return NavigationActionPolicy.ALLOW;
                            },
                      ),

                      if (_isLoading && !_hasError)
                        const Center(child: CircularProgressIndicator()),

                      // Barra Flutuante Arrastável
                      Positioned(
                        top: _posTop,
                        left: _posLeft,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              _posLeft += details.delta.dx;
                              _posTop += details.delta.dy;
                            });
                          },
                          child: Material(
                            color: Colors.transparent,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                  color: Colors.white24,
                                  width: 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 4.0,
                                    ),
                                    child: Icon(
                                      Icons.drag_indicator,
                                      color: Colors.white54,
                                      size: 18,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.arrow_back,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    tooltip: 'Voltar',
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(8),
                                    onPressed: _voltarComUrl,
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.refresh,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    tooltip: 'Recarregar',
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(8),
                                    onPressed: () {
                                      setState(() {
                                        _hasError = false;
                                        _isLoading = true;
                                      });
                                      webViewController?.reload();
                                    },
                                  ),
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.fullscreen,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                    tooltip: 'Tela Cheia (F11)',
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.all(8),
                                    onPressed: _toggleFullScreen,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
