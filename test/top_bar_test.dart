import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onde_parei/utils/classificacao.dart';
import 'package:onde_parei/widgets/barra_filtros.dart';
import 'package:onde_parei/widgets/top_bar.dart';

/// Monta a TopBar numa tela de [largura] e devolve os filtros entregues.
Future<List<FiltroLista>> _montar(
  WidgetTester tester, {
  required double largura,
  required bool isDesktop,
  FiltroLista filtro = const FiltroLista(),
  double escalaDoTexto = 1,
}) async {
  tester.view.physicalSize = Size(largura, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final recebidos = <FiltroLista>[];
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(escalaDoTexto)),
        child: child!,
      ),
      home: Scaffold(
        body: Column(
          children: [
            TopBar(
              showForm: false,
              onToggleForm: () {},
              isDesktop: isDesktop,
              onToggleTheme: () {},
              filtro: filtro,
              aoMudarFiltro: recebidos.add,
            ),
          ],
        ),
      ),
    ),
  );
  return recebidos;
}

Rect _busca(WidgetTester tester) => tester.getRect(find.byType(TextField));
Rect _menuDoTipo(WidgetTester tester) => tester.getRect(find.text('Tipo: '));

void main() {
  testWidgets('no computador largo, os filtros ficam à direita da busca', (
    tester,
  ) async {
    await _montar(tester, largura: 1800, isDesktop: true);

    expect(tester.takeException(), isNull);
    final busca = _busca(tester);
    final tipo = _menuDoTipo(tester);
    expect(tipo.left, greaterThan(busca.right));
    expect(tipo.center.dy, inInclusiveRange(busca.top, busca.bottom));
  });

  testWidgets('no computador estreito, os filtros descem para baixo da busca', (
    tester,
  ) async {
    await _montar(tester, largura: 1000, isDesktop: true);

    expect(tester.takeException(), isNull);
    expect(_menuDoTipo(tester).top, greaterThan(_busca(tester).bottom));
  });

  testWidgets('texto do sistema maior também desce os filtros', (tester) async {
    // Com o texto normal, 1800 de largura cabe os filtros na linha
    await _montar(tester, largura: 1800, isDesktop: true);
    expect(_menuDoTipo(tester).center.dy, lessThan(_busca(tester).bottom));

    await _montar(tester, largura: 1800, isDesktop: true, escalaDoTexto: 2);
    expect(_menuDoTipo(tester).top, greaterThan(_busca(tester).bottom));
  });

  testWidgets(
    'a largura medida é a da barra compacta com os nomes mais longos',
    (tester) async {
      late double medida;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                medida = BarraFiltros.larguraCompactaMaxima(context);
                return Align(
                  alignment: Alignment.topLeft,
                  child: BarraFiltros(
                    filtro: const FiltroLista(
                      tipo: FiltroTipo.semTipo,
                      status: StatusLeitura.planejoLer,
                    ),
                    aoMudar: (_) {},
                    compacta: true,
                  ),
                );
              },
            ),
          ),
        ),
      );

      final real = tester.getSize(find.byType(BarraFiltros)).width;
      expect(real, closeTo(medida, 0.5));
    },
  );

  testWidgets('no celular, os filtros ficam abaixo da busca', (tester) async {
    await _montar(tester, largura: 400, isDesktop: false);

    expect(tester.takeException(), isNull);
    expect(_menuDoTipo(tester).top, greaterThan(_busca(tester).bottom));
  });

  testWidgets(
    'na linha da busca, o limpar vira só o ícone e continua limpando',
    (tester) async {
      final recebidos = await _montar(
        tester,
        largura: 1800,
        isDesktop: true,
        filtro: const FiltroLista(
          busca: 'abc',
          tipo: FiltroTipo.semTipo,
          status: StatusLeitura.planejoLer,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Limpar filtros'), findsNothing);
      await tester.tap(find.byTooltip('Limpar filtros'));
      expect(recebidos, [const FiltroLista(busca: 'abc')]);
    },
  );

  testWidgets('abaixo da busca, o limpar mantém o texto', (tester) async {
    await _montar(
      tester,
      largura: 400,
      isDesktop: false,
      filtro: const FiltroLista(status: StatusLeitura.lendo),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Limpar filtros'), findsOneWidget);
  });
}
