// Falha rápido se alguma chamada ao sistema ficar sem resposta no teste
@Timeout(Duration(seconds: 60))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_manager/screens/leitor_base.dart';
import 'package:manga_manager/utils/browser_helper.dart';

/// Tela mínima com a base comum dos leitores, sem motor de navegador.
class _LeitorFalso extends StatefulWidget {
  const _LeitorFalso({required this.url});

  final String url;

  @override
  State<_LeitorFalso> createState() => _LeitorFalsoState();
}

class _LeitorFalsoState extends State<_LeitorFalso>
    with LeitorBase<_LeitorFalso> {
  @override
  String get urlInicial => widget.url;

  @override
  void initState() {
    super.initState();
    iniciarLeitor();
  }

  @override
  void dispose() {
    encerrarLeitor();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  const urlInicial = 'https://site.com/manga/one-piece/capitulo-10';

  Future<_LeitorFalsoState> montar(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: _LeitorFalso(url: urlInicial)),
    );
    return tester.state<_LeitorFalsoState>(find.byType(_LeitorFalso));
  }

  group('URL permitida', () {
    testWidgets('origem, subdomínio e lista; outro host não', (tester) async {
      final leitor = await montar(tester);
      leitor.allowedDomains = ['leituramanga.net'];

      expect(leitor.originHost, 'site.com');
      expect(leitor.urlPermitida('https://site.com/outro'), isTrue);
      expect(leitor.urlPermitida('https://img.site.com/a.png'), isTrue);
      expect(leitor.urlPermitida('https://leituramanga.net/cap-2'), isTrue);
      expect(leitor.urlPermitida('https://anuncio.com/?r=site.com'), isFalse);
      expect(leitor.urlPermitida('about:blank'), isFalse);
      expect(leitor.urlPermitida(''), isFalse);
    });

    testWidgets('registrarUrl guarda só a permitida e lê o capítulo da URL', (
      tester,
    ) async {
      final leitor = await montar(tester);

      expect(leitor.registrarUrl('https://anuncio.com/capitulo-99'), isFalse);
      expect(leitor.lastAllowedUrl, urlInicial);
      expect(leitor.detectedChapter, isNull);

      expect(leitor.registrarUrl('https://site.com/chapter/11/'), isTrue);
      expect(leitor.currentUrl, 'https://site.com/chapter/11/');
      expect(leitor.lastAllowedUrl, 'https://site.com/chapter/11/');
      expect(leitor.detectedChapter, 11);
    });
  });

  group('capítulo', () {
    testWidgets('título da página tem prioridade sobre a URL', (tester) async {
      final leitor = await montar(tester);

      leitor.aplicarCapituloDoTexto('One Piece - Capítulo 1100');
      expect(leitor.detectedChapter, 1100);
    });

    testWidgets('sem número no título usa a última URL permitida', (
      tester,
    ) async {
      final leitor = await montar(tester);

      leitor.aplicarCapituloDoTexto('One Piece');
      expect(leitor.detectedChapter, 10);
    });

    testWidgets('título com capítulo não consulta o cabeçalho', (tester) async {
      final leitor = await montar(tester);
      leitor.pageTitle = 'Capítulo 12';
      var consultou = false;

      await leitor.detectarCapituloDaPagina((script) async {
        consultou = true;
        return '';
      });

      expect(leitor.detectedChapter, 12);
      expect(consultou, isFalse);
    });

    testWidgets('sem capítulo no título lê o cabeçalho da página', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: _LeitorFalso(url: 'https://site.com/leitor')),
      );
      final leitor = tester.state<_LeitorFalsoState>(find.byType(_LeitorFalso));
      leitor.pageTitle = 'Leitor online';
      String? scriptRecebido;

      await leitor.detectarCapituloDaPagina((script) async {
        scriptRecebido = script;
        return 'Chapter 45 - O retorno';
      });

      expect(scriptRecebido, BrowserHelper.scriptTextoCabecalho);
      expect(leitor.detectedChapter, 45);
    });

    testWidgets('erro ao ler o cabeçalho não derruba a tela', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: _LeitorFalso(url: 'https://site.com/leitor')),
      );
      final leitor = tester.state<_LeitorFalsoState>(find.byType(_LeitorFalso));

      await leitor.detectarCapituloDaPagina(
        (script) async => throw Exception('motor indisponível'),
      );

      expect(leitor.detectedChapter, isNull);
    });
  });

  group('barra e saída', () {
    testWidgets('barra fora da tela volta para dentro', (tester) async {
      final leitor = await montar(tester);
      leitor.posLeft.value = 5000;
      leitor.posTop.value = -30;

      leitor.limitarPosicaoBarra();

      final tela = tester.view.physicalSize / tester.view.devicePixelRatio;
      expect(leitor.posLeft.value, tela.width - 48);
      expect(leitor.posTop.value, 0);
    });

    testWidgets('alternar a orientação funciona mesmo sem banco', (
      tester,
    ) async {
      final leitor = await montar(tester);

      // Banco e janela respondem por canais de plataforma: sem runAsync o
      // teste espera para sempre uma resposta que nunca chega
      await tester.runAsync(leitor.alternarOrientacaoBarra);
      expect(leitor.isVertical.value, isTrue);
    });

    testWidgets('voltar devolve a última URL permitida e o capítulo', (
      tester,
    ) async {
      Object? resultado;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                resultado = await Navigator.push<Object?>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const _LeitorFalso(url: urlInicial),
                  ),
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();

      final leitor = tester.state<_LeitorFalsoState>(find.byType(_LeitorFalso));
      leitor.registrarUrl('https://site.com/manga/one-piece/capitulo-11');
      leitor.registrarUrl('https://anuncio.com/popup');

      await tester.runAsync(leitor.voltarComResultado);
      await tester.pumpAndSettle();

      expect(resultado, {
        'url': 'https://site.com/manga/one-piece/capitulo-11',
        'capitulo': 11,
      });
    });
  });
}
