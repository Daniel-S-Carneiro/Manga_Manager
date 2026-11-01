import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_cef/webview_cef.dart';

import '../utils/browser_helper.dart';
import 'leitor_base.dart';

/// Leitor do Linux com webview_cef (o flutter_inappwebview estável não tem
/// Linux). O comportamento comum aos leitores fica em [LeitorBase].
///
/// Limitações do webview_cef em relação ao BrowserScreen: não há interceptação
/// de requisições nem cancelamento antes de navegar (a URL não permitida é
/// detectada depois e o leitor volta para a última permitida) e não há evento
/// de erro de carregamento (usa um tempo limite).
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

class _LinuxBrowserScreenState extends State<LinuxBrowserScreen>
    with LeitorBase<LinuxBrowserScreen> {
  WebViewController? _webViewController;
  bool _isReady = false;
  bool _initStarted = false;
  bool _redirecting = false;

  String _adBlockScriptCache = '';

  Timer? _loadTimeout;

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

  @override
  String get urlInicial => widget.initialUrl;

  @override
  void logLeitor(String mensagem) => _log(mensagem);

  @override
  void initState() {
    super.initState();
    iniciarLeitor();

    _log('initState', {
      'mangaTitle': widget.mangaTitle,
      'initialUrl': widget.initialUrl,
      'originHost': originHost,
    });

    carregarConfiguracoesBarra().then((_) => limitarPosicaoBarra());

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
        sessionOriginHost: originHost,
        // Com os logs ligados, a página anota falhas para o log ao fechar
        diagnostico: _kDebugLinuxBrowser,
        // O CEF não tem shouldOverrideUrlLoading: cancela pop-under por script
        bloquearNavegacaoPorScript: true,
      );
      allowedDomains = await BrowserHelper.getAllowedDomains();
      final stealth = BrowserHelper.stealthScript;

      _log('config', {
        'userAgent': userAgent,
        'originHost': originHost,
        'allowedDomains': allowedDomains,
        'adBlockScriptLen': _adBlockScriptCache.length,
      });

      // Sem o BrowserHelper.cliqueAgressivoScript: no CEF ele quebrou sites SPA
      // (testado), por isso o Linux fica só com o adblock "suave"
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
            pageTitle = title;
            aplicarCapituloDoTexto(title);
          },
          onUrlChanged: (url) {
            final allowed = registrarUrl(url);
            _log('EVENT onUrlChanged', {
              'url': url,
              'allowed': allowed,
              'originHost': originHost,
              'lastAllowed': lastAllowedUrl,
              'redirecting': _redirecting,
            });

            if (allowed) return;

            if (url.isEmpty || url.startsWith('about:')) {
              _log('URL intermediária ignorada', url);
              return;
            }

            final backTo = lastAllowedUrl ?? widget.initialUrl;
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
                !urlPermitida(url)) {
              return;
            }

            isLoading.value = true;
            hasError.value = false;
            _loadTimeout?.cancel();
            _loadTimeout = Timer(const Duration(seconds: 25), () {
              _log('TIMEOUT 25s');
              if (!mounted || !isLoading.value) return;
              final last = lastAllowedUrl;
              if (last != null && urlPermitida(last)) {
                isLoading.value = false;
                return;
              }
              isLoading.value = false;
              hasError.value = true;
              errorMessage.value =
                  'Tempo esgotado. Verifique a conexão com a internet.';
            });
          },
          onLoadEnd: (c, url) {
            _log('EVENT onLoadEnd', url);

            if (registrarUrl(url)) {
              _loadTimeout?.cancel();
              isLoading.value = false;
              hasError.value = false;
              // título / cabeçalho, como no BrowserScreen
              unawaited(
                detectarCapituloDaPagina(
                  (script) => c.evaluateJavascript(script),
                ),
              );
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
        hasError.value = true;
        errorMessage.value = 'Falha ao iniciar WebView: $e';
        isLoading.value = false;
      }
    }
  }

  @override
  void dispose() {
    _log('dispose', {'currentUrl': currentUrl, 'lastAllowed': lastAllowedUrl});
    _loadTimeout?.cancel();
    _webViewController?.dispose();
    encerrarLeitor();
    super.dispose();
  }

  // Registra o que a página anotou (requisições com erro, erros de JS e
  // navegações bloqueadas): é como investigamos falhas como "Erro ao carregar"
  @override
  Future<void> antesDeFechar() async {
    final c = _webViewController;
    if (!_kDebugLinuxBrowser || c == null) return;
    try {
      final diag = await c
          .evaluateJavascript(BrowserHelper.scriptLerDiagnostico)
          .timeout(const Duration(seconds: 2));
      _log('diagnóstico da página', diag);
    } catch (e) {
      _log('diagnóstico indisponível', e);
    }
  }

  void _onReload() {
    _log('onReload');
    final c = _webViewController;
    if (c == null) return;
    if (hasError.value) hasError.value = false;
    isLoading.value = true;
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
        await voltarComResultado();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            if (_isReady && !hasError.value && controller != null)
              controller.webviewWidget,

            ValueListenableBuilder<bool>(
              valueListenable: hasError,
              builder: (context, erro, _) {
                if (!erro) return const SizedBox.shrink();
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
                          valueListenable: errorMessage,
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
              valueListenable: isLoading,
              builder: (_, carregando, _) {
                if (carregando && !hasError.value) {
                  return const Center(child: CircularProgressIndicator());
                }
                return const SizedBox.shrink();
              },
            ),

            barraDeControle(tamanhoTela: screenSize, onRecarregar: _onReload),
          ],
        ),
      ),
    );
  }
}
