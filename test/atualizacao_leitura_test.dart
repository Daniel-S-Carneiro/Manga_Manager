import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onde_parei/widgets/atualizacao_leitura_dialog.dart';

void main() {
  group('MudancasLeitura.calcular', () {
    test('Map com link e capítulo novos', () {
      final m = MudancasLeitura.calcular(
        resultado: {'url': 'https://site.com/cap-11', 'capitulo': 11},
        linkSalvo: 'https://site.com/cap-10',
        capSalvo: 10,
      );
      expect(m.novoLink, 'https://site.com/cap-11');
      expect(m.novoCap, 11);
    });

    test('URL do leitor Linux (String) diferente da salva', () {
      final m = MudancasLeitura.calcular(
        resultado: 'https://site.com/cap-11',
        linkSalvo: 'https://site.com/cap-10',
        capSalvo: 10,
      );
      expect(m.novoLink, 'https://site.com/cap-11');
      expect(m.novoCap, isNull);
    });

    test('mesmo link com https:// acrescentado e "/" final não é mudança', () {
      final m = MudancasLeitura.calcular(
        resultado: 'https://site.com/manga/x/',
        linkSalvo: 'site.com/manga/x',
        capSalvo: 5,
      );
      expect(m.vazia, isTrue);
    });

    test('capítulo igual ao salvo não é mudança', () {
      final m = MudancasLeitura.calcular(
        resultado: {'url': 'https://site.com/cap-10', 'capitulo': 10},
        linkSalvo: 'https://site.com/cap-10',
        capSalvo: 10,
      );
      expect(m.vazia, isTrue);
    });

    test('capítulo nulo, zero ou negativo é ignorado', () {
      for (final cap in [null, 0, -1]) {
        final m = MudancasLeitura.calcular(
          resultado: {'url': 'https://site.com/x', 'capitulo': cap},
          linkSalvo: 'https://site.com/x',
          capSalvo: 10,
        );
        expect(m.vazia, isTrue, reason: 'capitulo = $cap');
      }
    });

    test('capítulo numérico não inteiro vira int', () {
      final m = MudancasLeitura.calcular(
        resultado: {'url': 'https://site.com/x', 'capitulo': 12.0},
        linkSalvo: 'https://site.com/x',
        capSalvo: 10,
      );
      expect(m.novoCap, 12);
    });

    test('leitor fechado sem resultado ou com link vazio não muda nada', () {
      for (final resultado in [
        null,
        '   ',
        {'url': '', 'capitulo': null},
      ]) {
        final m = MudancasLeitura.calcular(
          resultado: resultado,
          linkSalvo: 'https://site.com/x',
          capSalvo: 10,
        );
        expect(m.vazia, isTrue, reason: 'resultado = $resultado');
      }
    });
  });

  group('confirmarAtualizacaoLeitura', () {
    late EscolhaAtualizacao? escolha;
    late bool fechou;

    // Abre o diálogo a partir de um botão e guarda o que ele devolver
    Future<void> abrirDialogo(
      WidgetTester tester, {
      required MudancasLeitura mudancas,
      required int? capSalvo,
    }) async {
      escolha = null;
      fechou = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    escolha = await confirmarAtualizacaoLeitura(
                      context,
                      mudancas: mudancas,
                      capSalvo: capSalvo,
                    );
                    fechou = true;
                  },
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
    }

    ElevatedButton botaoAtualizar(WidgetTester tester) =>
        tester.widget(find.widgetWithText(ElevatedButton, 'Atualizar'));

    testWidgets('link e capítulo maior vêm marcados e são salvos', (
      tester,
    ) async {
      await abrirDialogo(
        tester,
        mudancas: const MudancasLeitura(
          novoLink: 'https://site.com/cap-11',
          novoCap: 11,
        ),
        capSalvo: 10,
      );

      expect(find.text('Capítulo: 10 → 11'), findsOneWidget);
      await tester.tap(find.text('Atualizar'));
      await tester.pumpAndSettle();

      expect(fechou, isTrue);
      expect(escolha, (salvarLink: true, salvarCap: true));
    });

    testWidgets('desmarcar o link salva só o capítulo', (tester) async {
      await abrirDialogo(
        tester,
        mudancas: const MudancasLeitura(
          novoLink: 'https://site.com/comentarios',
          novoCap: 11,
        ),
        capSalvo: 10,
      );

      await tester.tap(find.text('Link'));
      await tester.pump();
      await tester.tap(find.text('Atualizar'));
      await tester.pumpAndSettle();

      expect(escolha, (salvarLink: false, salvarCap: true));
    });

    testWidgets('capítulo menor vem desmarcado e exige marcação', (
      tester,
    ) async {
      await abrirDialogo(
        tester,
        mudancas: const MudancasLeitura(novoCap: 3),
        capSalvo: 10,
      );

      expect(
        find.text('Menor que o capítulo salvo. Confira antes de marcar.'),
        findsOneWidget,
      );
      expect(botaoAtualizar(tester).onPressed, isNull);

      await tester.tap(find.text('Capítulo: 10 → 3'));
      await tester.pump();
      expect(botaoAtualizar(tester).onPressed, isNotNull);

      await tester.tap(find.text('Atualizar'));
      await tester.pumpAndSettle();
      expect(escolha, (salvarLink: false, salvarCap: true));
    });

    testWidgets('Manter Anterior não salva nada', (tester) async {
      await abrirDialogo(
        tester,
        mudancas: const MudancasLeitura(
          novoLink: 'https://site.com/cap-11',
          novoCap: 11,
        ),
        capSalvo: 10,
      );

      await tester.tap(find.text('Manter Anterior'));
      await tester.pumpAndSettle();

      expect(fechou, isTrue);
      expect(escolha, isNull);
    });

    testWidgets('cabe numa tela de celular estreita', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await abrirDialogo(
        tester,
        mudancas: MudancasLeitura(
          novoLink: 'https://site.com/${'capitulo-muito-longo/' * 20}',
          novoCap: 1100,
        ),
        capSalvo: 1099,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Capítulo: 1099 → 1100'), findsOneWidget);
    });
  });
}
