import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_manager/utils/config_rolagem.dart';
import 'package:manga_manager/widgets/floating_control_bar.dart';
import 'package:manga_manager/widgets/painel_rolagem.dart';

void main() {
  group('PainelRolagem', () {
    late ValueNotifier<ConfigRolagem> config;
    late List<ConfigRolagem> confirmados;
    late int fechou;

    Future<void> montar(WidgetTester tester, ConfigRolagem inicial) async {
      config = ValueNotifier(inicial);
      confirmados = [];
      fechou = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PainelRolagem(
                config: config,
                onAlterando: (c) => config.value = c,
                onConfirmar: (c) {
                  confirmados.add(c);
                  config.value = c;
                },
                onFechar: () => fechou++,
              ),
            ),
          ),
        ),
      );
    }

    Slider slider(WidgetTester tester, String chave) =>
        tester.widget<Slider>(find.byKey(Key(chave)));

    testWidgets('mostra os valores atuais', (tester) async {
      await montar(
        tester,
        const ConfigRolagem(ativa: true, intensidade: 70, suavidade: 2),
      );

      expect(find.text('Distância por giro: 70%'), findsOneWidget);
      expect(find.text('Suavidade: Leve (2)'), findsOneWidget);
      expect(slider(tester, 'rolagem_intensidade').value, 70);
      expect(slider(tester, 'rolagem_suavidade').value, 2);
    });

    testWidgets('arrastar só muda o painel; soltar confirma', (tester) async {
      await montar(tester, ConfigRolagem.padrao);

      slider(tester, 'rolagem_intensidade').onChanged!(150);
      await tester.pump();
      expect(find.text('Distância por giro: 150%'), findsOneWidget);
      expect(confirmados, isEmpty);

      slider(tester, 'rolagem_intensidade').onChangeEnd!(150);
      slider(tester, 'rolagem_suavidade').onChangeEnd!(8);
      await tester.pump();
      expect(confirmados, [
        ConfigRolagem.padrao.copyWith(intensidade: 150),
        ConfigRolagem.padrao.copyWith(intensidade: 150, suavidade: 8),
      ]);
    });

    testWidgets('desligar confirma na hora e trava os controles', (
      tester,
    ) async {
      await montar(tester, ConfigRolagem.padrao);

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(confirmados.single.ativa, isFalse);
      expect(slider(tester, 'rolagem_intensidade').onChanged, isNull);
      expect(slider(tester, 'rolagem_suavidade').onChanged, isNull);
      expect(
        find.text('Desligada: o app não mexe na rolagem do navegador.'),
        findsOneWidget,
      );
    });

    testWidgets('restaurar padrão e fechar', (tester) async {
      await montar(
        tester,
        const ConfigRolagem(ativa: true, intensidade: 40, suavidade: 9),
      );

      await tester.tap(find.text('Restaurar padrão'));
      await tester.pump();
      expect(confirmados.single, ConfigRolagem.padrao);

      // Já no padrão, o botão fica desligado
      final botao = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Restaurar padrão'),
      );
      expect(botao.onPressed, isNull);

      await tester.tap(find.byTooltip('Fechar'));
      expect(fechou, 1);
    });
  });

  group('FloatingControlBar', () {
    Future<void> montarBarra(
      WidgetTester tester, {
      VoidCallback? onScrollSettings,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                FloatingControlBar(
                  posTop: ValueNotifier(20),
                  posLeft: ValueNotifier(20),
                  isVertical: ValueNotifier(false),
                  screenSize: const Size(800, 600),
                  onPanEnd: () {},
                  onBack: () {},
                  onReload: () {},
                  onFullScreen: () {},
                  onToggleOrientation: () {},
                  onScrollSettings: onScrollSettings,
                ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('botão da rolagem só aparece com a ação', (tester) async {
      await montarBarra(tester);
      expect(find.byTooltip('Rolagem do mouse'), findsNothing);

      var abriu = 0;
      await montarBarra(tester, onScrollSettings: () => abriu++);
      await tester.tap(find.byTooltip('Rolagem do mouse'));
      expect(abriu, 1);
    });
  });
}
