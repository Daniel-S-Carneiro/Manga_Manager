import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_manager/utils/licencas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Só as licenças registradas pelo app (o NOTICES do Flutter fica de fora)
  setUp(LicenseRegistry.reset);
  tearDown(LicenseRegistry.reset);

  test(
    'licença do CEF entra na tela de licenças no Windows e no Linux',
    () async {
      registrarLicencasExtras();
      final entradas = await LicenseRegistry.licenses.toList();

      final cef = entradas.where(
        (e) => e.packages.contains('Chromium Embedded Framework (CEF)'),
      );
      expect(cef, hasLength(1));
      final texto = cef.single.paragraphs.map((p) => p.text).join('\n');
      expect(texto, contains('Marshall A. Greenblatt'));
      // Aponta para os créditos completos do Chromium na pasta do programa
      expect(texto, contains('licencas/CHROMIUM_CREDITS.html'));
    },
    // O registro só vale onde o CEF vai no pacote
    skip: !(Platform.isWindows || Platform.isLinux),
  );
}
