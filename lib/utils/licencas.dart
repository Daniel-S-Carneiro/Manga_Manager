import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Licenças de terceiros que o Flutter não junta sozinho no NOTICES, para a
/// tela de licenças (`showLicensePage`, aberta pela janela de versão).
///
/// O NOTICES já traz os pacotes Dart e o próprio Flutter. Faltava o CEF: o
/// webview_cef põe o `libcef` no pacote do Windows e do Linux, e a licença
/// dele pede os avisos junto da distribuição. O texto completo dos
/// componentes do Chromium (CREDITS.html, ~19 MB) não entra no app: vai na
/// pasta `licencas` ao lado do executável (CMakeLists do Windows e do Linux).
void registrarLicencasExtras() {
  LicenseRegistry.addLicense(() async* {
    if (kIsWeb || !(Platform.isWindows || Platform.isLinux)) return;
    final cef = await rootBundle.loadString('assets/licencas/cef_LICENSE.txt');
    yield LicenseEntryWithLineBreaks(
      const ['Chromium Embedded Framework (CEF)'],
      '$cef\n'
      'Os avisos dos componentes de terceiros do Chromium, que vêm dentro do '
      'CEF, estão no arquivo licencas/CHROMIUM_CREDITS.html, na pasta do '
      'programa.',
    );
  });
}
