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

      io.File? dbExtraido;
      final dbName = kDebugMode ? 'manga_manager_debug.db' : 'manga_manager.db';

      for (var entity in extraidoDir.listSync(recursive: true)) {
        if (entity is io.File &&
            p.basename(entity.path).toLowerCase() == dbName.toLowerCase()) {
          dbExtraido = entity;
          break;
        }
      }

      if (dbExtraido == null) {
        throw Exception(
          "Banco de dados não encontrado no pacote de restauração.",
        );
      }

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

        await dbExtraido.copy(dbRealPath);

        final capasDirReal = await dbHelper.getCapasDirectory();
        if (capasDirReal.existsSync()) {
          capasDirReal.deleteSync(recursive: true);
        }
        capasDirReal.createSync(recursive: true);

        for (var entity in extraidoDir.listSync(recursive: true)) {
          if (entity is io.File &&
              p.basename(entity.path).toLowerCase() != dbName.toLowerCase()) {
            String nomeArquivo = p.basename(entity.path);
            await entity.copy(p.join(capasDirReal.path, nomeArquivo));
          }
        }
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
