import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/db_helper.dart';

/// Acha a biblioteca do Manga Manager (o app quando tinha o nome antigo,
/// até a v2.2.2) neste computador, para a importação direta.
///
/// Só no Windows e no Linux: no Android os dados de outro app ficam fora do
/// alcance, e a biblioteca passa pelo backup.
class ImportacaoMangaManager {
  ImportacaoMangaManager._();

  /// Pastas de dados do Manga Manager, ao lado da deste app ([pastaDeDados],
  /// a de `getApplicationSupportDirectory`). Ele usava o identificador
  /// `com.example`:
  /// - Windows: `%APPDATA%\io.github.danielscarneiro\OndeParei` aqui e
  ///   `%APPDATA%\com.example\manga_manager` lá.
  /// - Linux: `~/.local/share/io.github.danielscarneiro.ondeparei` aqui e
  ///   `~/.local/share/com.example.manga_manager` lá.
  ///
  /// A segunda pasta de cada lista é a de versões bem antigas.
  static List<String> pastasDoMangaManager(
    String pastaDeDados, {
    required bool windows,
  }) {
    if (windows) {
      final appData = p.windows.dirname(p.windows.dirname(pastaDeDados));
      return [
        p.windows.join(appData, 'com.example', 'manga_manager'),
        p.windows.join(appData, 'manga_manager'),
      ];
    }
    final dados = p.posix.dirname(pastaDeDados);
    return [
      p.posix.join(dados, 'com.example.manga_manager'),
      p.posix.join(dados, 'manga_manager'),
    ];
  }

  /// O banco do Manga Manager nas [pastas], se houver. Prefere o do mesmo
  /// modo deste app (o debug usa dados separados), mas aceita o outro.
  static io.File? bancoNasPastas(List<String> pastas, {required bool debug}) {
    final nomes = debug
        ? [DbHelper.nomeBancoDebugAntigo, DbHelper.nomeBancoReleaseAntigo]
        : [DbHelper.nomeBancoReleaseAntigo, DbHelper.nomeBancoDebugAntigo];
    for (final pasta in pastas) {
      for (final nome in nomes) {
        final banco = io.File(p.join(pasta, nome));
        if (banco.existsSync() && banco.lengthSync() > 0) return banco;
      }
    }
    return null;
  }

  /// O banco do Manga Manager neste computador, ou `null` (outro sistema,
  /// nunca instalado ou com os dados apagados na desinstalação).
  static Future<io.File?> localizarBanco() async {
    if (kIsWeb) return null;
    final windows = defaultTargetPlatform == TargetPlatform.windows;
    if (!windows && defaultTargetPlatform != TargetPlatform.linux) return null;
    try {
      final pastaDeDados = await getApplicationSupportDirectory();
      return bancoNasPastas(
        pastasDoMangaManager(pastaDeDados.path, windows: windows),
        debug: kDebugMode,
      );
    } catch (e) {
      debugPrint('Erro ao procurar o banco do Manga Manager: $e');
      return null;
    }
  }
}
