import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../database/db_helper.dart';
import '../utils/browser_helper.dart';
import '../widgets/floating_control_bar.dart';

/// Comportamento comum aos leitores, independente do motor do navegador
/// (BrowserScreen com flutter_inappwebview; LinuxBrowserScreen com webview_cef):
/// URL permitida, capítulo detectado, barra flutuante, tela cheia (F11) e o
/// resultado devolvido ao fechar (`{'url', 'capitulo'}`).
///
/// A tela chama [iniciarLeitor] no initState e [encerrarLeitor] no dispose, e
/// liga os eventos do seu navegador a [registrarUrl], [aplicarCapituloDoTexto]
/// e [detectarCapituloDaPagina].
mixin LeitorBase<T extends StatefulWidget> on State<T> {
  /// URL com que o leitor foi aberto.
  String get urlInicial;

  // ValueNotifiers para estado reativo sem reconstruir a tela inteira
  final ValueNotifier<bool> isLoading = ValueNotifier<bool>(true);
  final ValueNotifier<bool> hasError = ValueNotifier<bool>(false);
  final ValueNotifier<String> errorMessage = ValueNotifier<String>('');

  final ValueNotifier<double> posTop = ValueNotifier<double>(20.0);
  final ValueNotifier<double> posLeft = ValueNotifier<double>(20.0);
  final ValueNotifier<bool> isVertical = ValueNotifier<bool>(false);

  /// Host da URL inicial: navegar dentro dele (ou de um subdomínio) é sempre
  /// permitido.
  String originHost = '';
  String? currentUrl;
  String? lastAllowedUrl;
  int? detectedChapter;
  String? pageTitle;

  /// Domínios permitidos além da origem (padrão + banco).
  List<String> allowedDomains = BrowserHelper.defaultAllowedDomains;

  bool _telaCheiaMobile = false;

  bool get leitorDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// Mensagens de depuração; cada tela decide se e como registra.
  void logLeitor(String mensagem) {}

  void iniciarLeitor() {
    originHost = BrowserHelper.originHostFromUrl(urlInicial) ?? '';
    lastAllowedUrl = urlInicial;
    HardwareKeyboard.instance.addHandler(_teclaGlobal);
  }

  void encerrarLeitor() {
    HardwareKeyboard.instance.removeHandler(_teclaGlobal);
    if (leitorDesktop) {
      unawaited(_restaurarJanela());
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    isLoading.dispose();
    hasError.dispose();
    errorMessage.dispose();
    posTop.dispose();
    posLeft.dispose();
    isVertical.dispose();
  }

  // ---------------------------------------------------------------------------
  // URL E CAPÍTULO
  // ---------------------------------------------------------------------------

  /// Permitida: o host da origem (ou subdomínio) ou um domínio da lista,
  /// sempre comparando o HOST (um domínio permitido escondido na query string
  /// não libera a navegação).
  bool urlPermitida(String url) {
    if (url.isEmpty || url.startsWith('about:') || url.startsWith('data:')) {
      return false;
    }
    if (originHost.isNotEmpty &&
        BrowserHelper.isSameOriginHost(url, originHost)) {
      return true;
    }
    return BrowserHelper.hostMatchesAllowed(url, allowedDomains);
  }

  /// Guarda a URL como atual (e o capítulo que ela indicar) se for permitida.
  /// Devolve se a URL é permitida.
  bool registrarUrl(String url) {
    if (!urlPermitida(url)) return false;
    currentUrl = url;
    lastAllowedUrl = url;
    final cap = BrowserHelper.parseChapterFromUrl(url);
    if (cap != null) detectedChapter = cap;
    return true;
  }

  /// Capítulo pelo texto (título da página, cabeçalho...), com a última URL
  /// permitida como reserva.
  void aplicarCapituloDoTexto(String? texto) {
    final cap = BrowserHelper.parseChapter(
      title: texto,
      url: lastAllowedUrl ?? currentUrl,
    );
    if (cap != null) {
      detectedChapter = cap;
      logLeitor('Capítulo detectado: $cap | texto: $texto');
    }
  }

  /// Tenta o título da página e, se ainda não houver capítulo, o texto do
  /// cabeçalho. [avaliarJs] executa um script no navegador e devolve o valor.
  Future<void> detectarCapituloDaPagina(
    Future<Object?> Function(String script) avaliarJs,
  ) async {
    aplicarCapituloDoTexto(pageTitle);
    if (detectedChapter != null) return;

    try {
      final texto = await avaliarJs(BrowserHelper.scriptTextoCabecalho);
      if (texto != null) aplicarCapituloDoTexto(texto.toString());
    } catch (e) {
      logLeitor('Falha ao ler o cabeçalho da página: $e');
    }
  }

  /// O que o leitor devolve ao fechar (lido por MudancasLeitura no card).
  Map<String, Object?> resultadoLeitor() => {
    'url': lastAllowedUrl ?? currentUrl ?? urlInicial,
    'capitulo': detectedChapter,
  };

  // ---------------------------------------------------------------------------
  // BARRA FLUTUANTE
  // ---------------------------------------------------------------------------

  Future<void> carregarConfiguracoesBarra() async {
    try {
      final db = DbHelper();
      final xStr = await db.getConfig('barra_x');
      final yStr = await db.getConfig('barra_y');
      final isVertStr = await db.getConfig('barra_vertical');
      if (!mounted) return;

      if (xStr != null) posLeft.value = double.tryParse(xStr) ?? 20.0;
      if (yStr != null) posTop.value = double.tryParse(yStr) ?? 20.0;
      if (isVertStr != null) isVertical.value = isVertStr == 'true';
    } catch (e) {
      logLeitor('Erro ao carregar config da barra: $e');
    }
  }

  /// Garante que a barra não abra fora da tela (janela menor, zoom diferente...)
  void limitarPosicaoBarra() {
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    const double minVisivel = 48;

    final maxLeft = (size.width - minVisivel).clamp(0.0, double.infinity);
    final maxTop = (size.height - minVisivel).clamp(0.0, double.infinity);

    posLeft.value = posLeft.value.clamp(0.0, maxLeft).toDouble();
    posTop.value = posTop.value.clamp(0.0, maxTop).toDouble();
  }

  Future<void> salvarPosicaoBarra() async {
    try {
      final db = DbHelper();
      // Uma casa decimal basta (antes salvava 31.33333333333313)
      await db.setConfig('barra_x', posLeft.value.toStringAsFixed(1));
      await db.setConfig('barra_y', posTop.value.toStringAsFixed(1));
    } catch (e) {
      logLeitor('Erro ao salvar posição da barra: $e');
    }
  }

  Future<void> alternarOrientacaoBarra() async {
    isVertical.value = !isVertical.value;
    try {
      await DbHelper().setConfig('barra_vertical', isVertical.value.toString());
    } catch (e) {
      logLeitor('Erro ao salvar orientação da barra: $e');
    }
  }

  /// Barra flutuante com as ações comuns; só recarregar depende do motor.
  Widget barraDeControle({
    required Size tamanhoTela,
    required VoidCallback onRecarregar,
  }) {
    return FloatingControlBar(
      posTop: posTop,
      posLeft: posLeft,
      isVertical: isVertical,
      screenSize: tamanhoTela,
      onPanEnd: salvarPosicaoBarra,
      onBack: voltarComResultado,
      onReload: onRecarregar,
      onFullScreen: alternarTelaCheia,
      onToggleOrientation: alternarOrientacaoBarra,
    );
  }

  // ---------------------------------------------------------------------------
  // TELA CHEIA E SAÍDA
  // ---------------------------------------------------------------------------

  bool _teclaGlobal(KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.f11) {
      alternarTelaCheia();
      return true;
    }
    return false;
  }

  Future<void> alternarTelaCheia() async {
    if (leitorDesktop) {
      try {
        final novoEstado = !(await windowManager.isFullScreen());
        await windowManager.setTitleBarStyle(
          novoEstado ? TitleBarStyle.hidden : TitleBarStyle.normal,
        );
        await windowManager.setFullScreen(novoEstado);
      } catch (e) {
        logLeitor('Erro na tela cheia: $e');
      }
    } else {
      _telaCheiaMobile = !_telaCheiaMobile;
      SystemChrome.setEnabledSystemUIMode(
        _telaCheiaMobile
            ? SystemUiMode.immersiveSticky
            : SystemUiMode.edgeToEdge,
      );
    }
  }

  // Futures sem await dentro de um try síncrono não têm os erros capturados,
  // então a restauração da janela fica numa função própria.
  Future<void> _restaurarJanela() async {
    try {
      await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      await windowManager.setFullScreen(false);
    } catch (_) {}
  }

  /// Sai da tela cheia e fecha o leitor devolvendo [resultadoLeitor].
  Future<void> voltarComResultado() async {
    if (leitorDesktop) {
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
      final resultado = resultadoLeitor();
      logLeitor('Fechando o leitor: $resultado');
      Navigator.pop(context, resultado);
    }
  }
}
