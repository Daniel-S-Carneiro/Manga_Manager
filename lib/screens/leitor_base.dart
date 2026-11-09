import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../database/db_helper.dart';
import '../utils/browser_helper.dart';
import '../utils/config_rolagem.dart';
import '../utils/config_sobreposicoes.dart';
import '../widgets/floating_control_bar.dart';
import '../widgets/painel_rolagem.dart';

/// Comportamento comum aos leitores, independente do motor do navegador
/// (BrowserScreen com flutter_inappwebview; LinuxBrowserScreen com webview_cef):
/// URL permitida, capítulo detectado, barra flutuante, rolagem do mouse, tela
/// cheia (F11) e o resultado devolvido ao fechar (`{'url', 'capitulo'}`).
///
/// A tela chama [iniciarLeitor] no initState e [encerrarLeitor] no dispose, e
/// liga os eventos do seu navegador a [registrarUrl], [aplicarCapituloDoTexto]
/// e [detectarCapituloDaPagina]. Para a rolagem, informa [fatorBaseRolagem],
/// injeta o [scriptRolagem] e implementa [aplicarRolagem].
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

  // Rolagem do mouse (painel aberto pela barra; só desktop)
  final ValueNotifier<ConfigRolagem> configRolagem =
      ValueNotifier<ConfigRolagem>(ConfigRolagem.padrao);
  final ValueNotifier<bool> painelRolagemAberto = ValueNotifier<bool>(false);

  /// Regra que esconde avisos por cima da página, ligada ou não no site aberto
  /// (botão da barra; ver [ConfigSobreposicoes]).
  final ValueNotifier<bool> sobreposicoesAtivas = ValueNotifier<bool>(true);

  /// Host da URL inicial: navegar no domínio do site (sem o "www.") ou num
  /// subdomínio dele é sempre permitido ([BrowserHelper.isSameOriginHost]).
  String originHost = '';
  String? currentUrl;
  String? lastAllowedUrl;
  int? detectedChapter;
  String? pageTitle;

  /// Domínios que o usuário liberou além do site do link (lidos do banco). O
  /// app não traz nenhum embutido (docs/diretrizes-projeto.md).
  List<String> allowedDomains = const [];

  bool _telaCheiaMobile = false;

  bool get leitorDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  /// Mensagens de depuração; cada tela decide se e como registra.
  void logLeitor(String mensagem) {}

  /// Chamado ao fechar, antes de sair da tela (ex.: registrar o diagnóstico da
  /// página). Falhas aqui não impedem o fechamento.
  Future<void> antesDeFechar() async {}

  /// Quanto o script de rolagem multiplica o giro que a página recebe, para
  /// desfazer o exagero do plugin (ver [BrowserHelper.scriptRolagem]). Cada
  /// tela informa o do seu motor.
  double get fatorBaseRolagem => 1.0;

  /// Aplica [script] (o [scriptRolagem] atual) na página aberta e nas
  /// próximas. Cada tela liga ao seu navegador.
  Future<void> aplicarRolagem(String script) async {}

  /// Aplica [script] (o [scriptSobreposicoes] atual) na página aberta e nas
  /// próximas. Cada tela liga ao seu navegador, como em [aplicarRolagem].
  Future<void> aplicarSobreposicoes(String script) async {}

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
    configRolagem.dispose();
    painelRolagemAberto.dispose();
    sobreposicoesAtivas.dispose();
  }

  // ---------------------------------------------------------------------------
  // URL E CAPÍTULO
  // ---------------------------------------------------------------------------

  /// Permitida: o site da origem (ou subdomínio) ou um domínio da lista,
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
      onScrollSettings: leitorDesktop ? alternarPainelRolagem : null,
      sobreposicoesAtivas: sobreposicoesAtivas,
      onAlternarSobreposicoes: alternarSobreposicoes,
    );
  }

  // ---------------------------------------------------------------------------
  // AVISOS POR CIMA DA PÁGINA (SOBREPOSIÇÕES)
  // ---------------------------------------------------------------------------

  /// Script que liga ou desliga a regra no site aberto.
  String get scriptSobreposicoes =>
      BrowserHelper.scriptSobreposicoes(ativa: sobreposicoesAtivas.value);

  String get _dominioDoSite => BrowserHelper.dominioDoSite(originHost);

  /// Lê se a regra está ligada no site; a tela chama antes de montar os
  /// scripts.
  Future<void> carregarConfiguracaoSobreposicoes() async {
    if (_dominioDoSite.isEmpty) return;
    try {
      final ativa = await ConfigSobreposicoes.ativaNoSite(_dominioDoSite);
      if (!mounted) return;
      sobreposicoesAtivas.value = ativa;
      if (!ativa) logLeitor('Avisos por cima da página: regra desligada aqui');
    } catch (e) {
      logLeitor('Erro ao carregar a regra de sobreposições: $e');
    }
  }

  /// Botão da barra: liga ou desliga a regra no site aberto, na hora (sem
  /// recarregar), e grava para as próximas vezes.
  Future<void> alternarSobreposicoes() async {
    final ativa = !sobreposicoesAtivas.value;
    sobreposicoesAtivas.value = ativa;
    logLeitor(
      'Avisos por cima da página: ${ativa ? 'escondidos' : 'mostrados'}',
    );
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              ativa
                  ? 'Avisos por cima da página serão escondidos neste site'
                  : 'Avisos por cima da página serão mostrados neste site',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
    }
    try {
      await aplicarSobreposicoes(scriptSobreposicoes);
    } catch (e) {
      logLeitor('Falha ao aplicar a regra de sobreposições: $e');
    }
    if (_dominioDoSite.isEmpty) return;
    try {
      await ConfigSobreposicoes.definir(_dominioDoSite, ativa: ativa);
    } catch (e) {
      logLeitor('Erro ao salvar a regra de sobreposições: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // ROLAGEM DO MOUSE
  // ---------------------------------------------------------------------------

  /// Script de rolagem com a configuração atual.
  String get scriptRolagem => BrowserHelper.scriptRolagem(
    configRolagem.value,
    fatorBase: fatorBaseRolagem,
  );

  /// Lê a configuração salva; a tela chama antes de montar os scripts.
  Future<void> carregarConfiguracoesRolagem() async {
    try {
      final config = await ConfigRolagem.carregar();
      if (!mounted) return;
      configRolagem.value = config;
      logLeitor(
        'Rolagem: $config, fator base '
        '${fatorBaseRolagem.toStringAsFixed(3)}',
      );
    } catch (e) {
      logLeitor('Erro ao carregar config da rolagem: $e');
    }
  }

  /// Configuração nova vinda do painel: vale na hora, na página aberta e nas
  /// próximas, e com [salvar] fica gravada para os outros capítulos.
  Future<void> mudarRolagem(ConfigRolagem nova, {bool salvar = true}) async {
    configRolagem.value = nova;
    logLeitor('Rolagem alterada: $nova');
    try {
      await aplicarRolagem(scriptRolagem);
    } catch (e) {
      logLeitor('Falha ao aplicar a rolagem: $e');
    }
    if (!salvar) return;
    try {
      await nova.salvar();
    } catch (e) {
      logLeitor('Erro ao salvar a rolagem: $e');
    }
  }

  void alternarPainelRolagem() {
    painelRolagemAberto.value = !painelRolagemAberto.value;
  }

  /// Painel da rolagem, do lado oposto ao da barra para não cobrir os botões.
  /// Fica no Stack da tela, junto da [barraDeControle].
  Widget painelDeRolagem({required Size tamanhoTela}) {
    return ListenableBuilder(
      listenable: Listenable.merge([painelRolagemAberto, posTop]),
      builder: (context, _) {
        if (!painelRolagemAberto.value) return const SizedBox.shrink();
        final barraEmCima = posTop.value < tamanhoTela.height / 2;
        return Positioned(
          left: 0,
          right: 0,
          top: barraEmCima ? null : 16,
          bottom: barraEmCima ? 16 : null,
          child: Center(
            child: PainelRolagem(
              config: configRolagem,
              onAlterando: (c) => configRolagem.value = c,
              onConfirmar: (c) => unawaited(mudarRolagem(c)),
              onFechar: () => painelRolagemAberto.value = false,
            ),
          ),
        );
      },
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

    try {
      await antesDeFechar();
    } catch (e) {
      logLeitor('Falha antes de fechar: $e');
    }

    if (mounted) {
      final resultado = resultadoLeitor();
      logLeitor('Fechando o leitor: $resultado');
      Navigator.pop(context, resultado);
    }
  }
}
