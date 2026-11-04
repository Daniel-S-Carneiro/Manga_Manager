import 'dart:io' as io;
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/db_helper.dart';
import '../utils/tar_stream_helper.dart';

class BackupService {
  static const bool _kVerboseMode = true;

  static void _logDebug(String mensagem) {
    if (_kVerboseMode) {
      debugPrint('[BackupService] $mensagem');
    }
  }

  // ==========================================
  // ISOLATE DE COMPRESSÃO (PACKAGE:TAR + GZIP)
  // ==========================================
  static Future<String?> _compressIsolate(Map<String, String> args) async {
    try {
      final dbPath = args['dbPath']!;
      final capasDirPath = args['capasDirPath']!;
      final tarGzPath = args['tarGzPath']!;

      _logDebug(
        'Iniciando compressão TAR.GZ via pacote oficial (package:tar)...',
      );

      await TarStreamHelper.compressToTarGz(
        dbPath: dbPath,
        capasDirPath: capasDirPath,
        tarGzPath: tarGzPath,
      );

      _logDebug('Compressão Concluída com Sucesso!');
      return tarGzPath;
    } catch (e, st) {
      _logDebug('ERRO NA COMPRESSÃO: $e\n$st');
      return null;
    }
  }

  // ==========================================
  // ISOLATE DE EXTRAÇÃO (PACKAGE:TAR + GZIP)
  // ==========================================
  static Future<bool> _extractIsolate(Map<String, String> args) async {
    try {
      final tarGzPath = args['tarGzPath']!;
      final destPath = args['destPath']!;

      _logDebug(
        'Iniciando Extração TAR.GZ via pacote oficial com proteção de Path Traversal...',
      );

      await TarStreamHelper.extractTarGz(
        tarGzPath: tarGzPath,
        destPath: destPath,
      );

      _logDebug('Extração concluída com sucesso.');
      return true;
    } catch (e, st) {
      _logDebug('ERRO NA EXTRAÇÃO STREAMING: $e\n$st');
      return false;
    }
  }

  /// O banco dentro do backup. Prefere o do modo atual, mas aceita o do outro:
  /// um backup do app instalado (`manga_manager.db`) também restaura no debug,
  /// e o contrário também.
  static io.File? bancoDoBackup(List<io.File> arquivos, {required bool debug}) {
    final preferidos = debug
        ? [DbHelper.nomeBancoDebug, DbHelper.nomeBancoRelease]
        : [DbHelper.nomeBancoRelease, DbHelper.nomeBancoDebug];
    for (final nome in preferidos) {
      for (final arquivo in arquivos) {
        if (p.basename(arquivo.path).toLowerCase() == nome) return arquivo;
      }
    }
    return null;
  }

  static bool _ehArquivoDeBanco(String caminho) {
    final nome = p.basename(caminho).toLowerCase();
    return nome.endsWith('.db') ||
        nome.endsWith('.db-journal') ||
        nome.endsWith('.db-wal') ||
        nome.endsWith('.db-shm');
  }

  // ==========================================
  // FUNÇÕES PÚBLICAS
  // ==========================================
  Future<String> exportBackup(String saveFileFinalPath) async {
    final dbHelper = DbHelper();
    dbHelper.lockDatabase();

    try {
      final dbPath = await dbHelper.getDatabasePathString();
      final capasDir = await dbHelper.getCapasDirectory();

      await dbHelper.closeDatabase();

      final tempDir = await getTemporaryDirectory();
      final tempTarGzPath = p.join(
        tempDir.path,
        'temp_backup_${DateTime.now().millisecondsSinceEpoch}.tar.gz',
      );

      final resultPath = await Isolate.run(
        () => _compressIsolate({
          'dbPath': dbPath,
          'capasDirPath': capasDir.path,
          'tarGzPath': tempTarGzPath,
        }),
      );

      if (resultPath == null || !io.File(resultPath).existsSync()) {
        throw Exception(
          "Falha ao gerar o arquivo de backup compactado. Verifique os logs.",
        );
      }

      await io.File(resultPath).copy(saveFileFinalPath);
      io.File(resultPath).deleteSync();

      return saveFileFinalPath;
    } finally {
      await dbHelper.reopenDatabase();
      dbHelper.unlockDatabase();
    }
  }

  Future<String> restoreBackup(
    String tarGzFilePath, {
    required bool merge,
  }) async {
    final dbHelper = DbHelper();
    dbHelper.lockDatabase();
    io.Directory? extraidoDir;

    try {
      final tempDir = await getTemporaryDirectory();
      final destPath = p.join(
        tempDir.path,
        'restore_${DateTime.now().millisecondsSinceEpoch}',
      );
      extraidoDir = io.Directory(destPath);

      final sucesso = await Isolate.run(
        () =>
            _extractIsolate({'tarGzPath': tarGzFilePath, 'destPath': destPath}),
      );

      if (!sucesso) {
        throw Exception(
          "Falha ao descompactar o arquivo .tar.gz. Verifique se o arquivo não está corrompido.",
        );
      }

      final arquivos = extraidoDir
          .listSync(recursive: true)
          .whereType<io.File>()
          .toList();
      final dbExtraido = bancoDoBackup(arquivos, debug: kDebugMode);

      if (dbExtraido == null) {
        throw Exception(
          "Banco de dados não encontrado no pacote de restauração.",
        );
      }
      _logDebug('Banco do backup: ${p.basename(dbExtraido.path)}');

      if (merge) {
        await dbHelper.reopenDatabase();
        int inseridos = await dbHelper.mergeFromBackup(
          dbExtraido.path,
          extraidoDir,
        );
        return 'Mesclagem concluída: $inseridos novos mangás inseridos.';
      } else {
        await dbHelper.closeDatabase();
        final dbRealPath = await dbHelper.getDatabasePathString();

        // Um diário do SQLite que sobrasse do banco antigo seria aplicado no
        // banco novo e o corromperia
        for (final sufixo in ['-journal', '-wal', '-shm']) {
          final resto = io.File('$dbRealPath$sufixo');
          if (resto.existsSync()) resto.deleteSync();
        }
        await dbExtraido.copy(dbRealPath);

        final capasDirReal = await dbHelper.getCapasDirectory();
        if (capasDirReal.existsSync()) {
          capasDirReal.deleteSync(recursive: true);
        }
        capasDirReal.createSync(recursive: true);

        final capasDoBackup = <String, String>{};
        for (final arquivo in arquivos) {
          if (_ehArquivoDeBanco(arquivo.path)) continue;
          final nome = p.basename(arquivo.path);
          await arquivo.copy(p.join(capasDirReal.path, nome));
          capasDoBackup[nome.toLowerCase()] = nome;
        }

        // O banco guarda o caminho das capas no aparelho de origem
        final corrigidas = await dbHelper.corrigirCaminhosDasCapas(
          capasDirReal.path,
          capasDoBackup,
        );
        _logDebug('Capas apontadas para ${capasDirReal.path}: $corrigidas');
        return 'Backup substituído e restaurado com sucesso!';
      }
    } finally {
      if (extraidoDir != null && extraidoDir.existsSync()) {
        try {
          extraidoDir.deleteSync(recursive: true);
        } catch (_) {}
      }
      await dbHelper.reopenDatabase();
      dbHelper.unlockDatabase();
    }
  }
}
