// Falha rápido se alguma chamada ficar sem resposta
@Timeout(Duration(seconds: 60))
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_manager/widgets/version_updater_button.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'manga_manager',
      packageName: 'com.example.manga_manager',
      version: '2.1.0',
      buildNumber: '2',
      buildSignature: '',
    );
  });

  // Telas de celular estreitas: o título do diálogo estourava a largura
  for (final largura in [320.0, 360.0, 393.0]) {
    testWidgets('diálogo de versão cabe numa tela de $largura', (tester) async {
      tester.view.physicalSize = Size(largura, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // Nos testes o HttpClient responde 400: o botão mostra "Indisponível"
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: VersionUpdaterButton())),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(VersionUpdaterButton));
      await tester.pumpAndSettle();

      expect(find.text('Informações de Versão'), findsOneWidget);
      // Um RenderFlex que estoura a largura vira exceção no teste
      expect(tester.takeException(), isNull);
    });
  }
}
