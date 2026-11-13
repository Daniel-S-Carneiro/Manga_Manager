import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onde_parei/utils/classificacao.dart';
import 'package:onde_parei/widgets/barra_filtros.dart';
import 'package:onde_parei/widgets/manga_card.dart';
import 'package:onde_parei/widgets/seletor_classificacao.dart';

Widget _app(Widget filho, {double largura = 400}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: largura, child: filho),
    ),
  ),
);

void main() {
  group('SeletorMenu', () {
    testWidgets('escolher "Sem tipo" depois de um tipo entrega nulo', (
      tester,
    ) async {
      String? tipo = 'manhwa';
      var chamadas = 0;
      await tester.pumpWidget(
        _app(
          StatefulBuilder(
            builder: (context, setState) => SeletorMenu<String?>(
              rotulo: 'Tipo',
              opcoes: opcoesDeTipo,
              selecionado: tipo,
              aoSelecionar: (novo) => setState(() {
                tipo = novo;
                chamadas++;
              }),
            ),
          ),
        ),
      );
      expect(find.text('Manhwa'), findsOneWidget);

      await tester.tap(find.text('Manhwa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sem tipo').last);
      await tester.pumpAndSettle();

      // O PopupMenuButton trataria um valor nulo como "fechou sem escolher"
      expect(chamadas, 1);
      expect(tipo, isNull);
      expect(find.text('Sem tipo'), findsOneWidget);
    });

    testWidgets('chave desconhecida aparece como "Sem tipo" e não muda '
        'sozinha', (tester) async {
      var chamadas = 0;
      await tester.pumpWidget(
        _app(
          SeletorMenu<String?>(
            rotulo: 'Tipo',
            opcoes: opcoesDeTipo,
            selecionado: 'chave_do_futuro',
            aoSelecionar: (_) => chamadas++,
          ),
        ),
      );
      expect(find.text('Sem tipo'), findsOneWidget);
      expect(chamadas, 0);
    });

    testWidgets('lista todos os tipos e cabe na largura de um celular', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          SeletorMenu<String?>(
            rotulo: 'Tipo',
            opcoes: opcoesDeTipo,
            selecionado: null,
            aoSelecionar: (_) {},
          ),
          largura: 280,
        ),
      );
      await tester.tap(find.text('Sem tipo'));
      await tester.pumpAndSettle();
      for (final tipo in TipoLeitura.todos) {
        expect(find.text(tipo.nome), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  });

  group('BarraFiltros', () {
    Future<List<FiltroLista>> montar(
      WidgetTester tester,
      FiltroLista filtro, {
      double largura = 400,
    }) async {
      final recebidos = <FiltroLista>[];
      await tester.pumpWidget(
        _app(
          BarraFiltros(filtro: filtro, aoMudar: recebidos.add),
          largura: largura,
        ),
      );
      return recebidos;
    }

    testWidgets('sem filtro mostra "Todos" e não mostra o limpar', (
      tester,
    ) async {
      await montar(tester, const FiltroLista());
      expect(find.text('Tipo: '), findsOneWidget);
      expect(find.text('Status: '), findsOneWidget);
      expect(find.text('Todos'), findsNWidgets(2));
      expect(find.text('Limpar filtros'), findsNothing);
    });

    testWidgets('escolher um tipo mantém a busca e o status', (tester) async {
      const filtro = FiltroLista(busca: 'x', status: StatusLeitura.lendo);
      final recebidos = await montar(tester, filtro);

      await tester.tap(find.text('Tipo: '));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Manhwa'));
      await tester.pumpAndSettle();

      expect(recebidos, [
        const FiltroLista(
          busca: 'x',
          tipo: FiltroTipo.de(TipoLeitura.manhwa),
          status: StatusLeitura.lendo,
        ),
      ]);
    });

    testWidgets('"Sem tipo" no filtro e "Todos" no status', (tester) async {
      const filtro = FiltroLista(status: StatusLeitura.completo);
      final recebidos = await montar(tester, filtro);

      await tester.tap(find.text('Tipo: '));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sem tipo'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Status: '));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Todos').last);
      await tester.pumpAndSettle();

      expect(recebidos, [
        const FiltroLista(
          tipo: FiltroTipo.semTipo,
          status: StatusLeitura.completo,
        ),
        const FiltroLista(),
      ]);
    });

    testWidgets('escolher o que já está marcado não recarrega', (tester) async {
      final recebidos = await montar(tester, const FiltroLista());
      await tester.tap(find.text('Status: '));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Todos').last);
      await tester.pumpAndSettle();
      expect(recebidos, isEmpty);
    });

    testWidgets('limpar tira tipo e status e mantém a busca', (tester) async {
      const filtro = FiltroLista(
        busca: 'abc',
        tipo: FiltroTipo.de(TipoLeitura.novel),
        status: StatusLeitura.planejoLer,
      );
      final recebidos = await montar(tester, filtro);
      expect(find.text('Novel'), findsOneWidget);
      expect(find.text('Planejo Ler'), findsOneWidget);

      await tester.tap(find.text('Limpar filtros'));
      expect(recebidos, [const FiltroLista(busca: 'abc')]);
    });

    testWidgets('quebra a linha num celular estreito sem estourar', (
      tester,
    ) async {
      await montar(
        tester,
        const FiltroLista(
          tipo: FiltroTipo.semTipo,
          status: StatusLeitura.planejoLer,
        ),
        largura: 300,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Limpar filtros'), findsOneWidget);
    });
  });

  group('selo do tipo no card', () {
    Future<void> card(WidgetTester tester, String? tipo) => tester.pumpWidget(
      _app(
        SizedBox(
          height: 515,
          child: MangaCardWidget(
            manga: {
              'id': 1,
              'nome_pt': 'Nome',
              'status_leitura': 'Planejo Ler',
              'tipo': tipo,
            },
            onDelete: () {},
            onUpdate: () {},
          ),
        ),
        largura: 150,
      ),
    );

    testWidgets('mostra o tipo junto com o status', (tester) async {
      await card(tester, 'webtoon');
      expect(find.text('WEBTOON'), findsOneWidget);
      expect(find.text('PLANEJO LER'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sem tipo ou com chave desconhecida não mostra selo', (
      tester,
    ) async {
      for (final tipo in [null, 'chave_do_futuro']) {
        await card(tester, tipo);
        for (final t in TipoLeitura.todos) {
          expect(find.text(t.nome.toUpperCase()), findsNothing);
        }
        expect(find.text('PLANEJO LER'), findsOneWidget);
      }
    });
  });
}
