import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive_io.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import '../controllers/refresh_controller.dart';

class BackupManagerButton extends StatefulWidget {
  final VoidCallback onBackupRestored;

  const BackupManagerButton({super.key, required this.onBackupRestored});

  @override
  State<BackupManagerButton> createState() => _BackupManagerButtonState();

  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () {
        globalRefreshController.refresh();
      },
      child: const Text("Restaurar Backup"),
    );
  }
}

class _BackupManagerButtonState extends State<BackupManagerButton> {
  bool _isLoading = false;

  Future<Map<String, String>> _obterCaminhos() async {
    String dbPath;
    String capasDirPath;

    final nomeDb = kDebugMode ? 'manga_manager_debug.db' : 'manga_manager.db';
    final nomePastaCapas = kDebugMode
        ? 'manga_manager_capas_debug'
        : 'manga_manager_capas';

    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      final directory = await getApplicationSupportDirectory();
      dbPath = p.join(directory.path, nomeDb);

      final docsDir = await getApplicationDocumentsDirectory();
      capasDirPath = p.join(docsDir.path, nomePastaCapas);
    } else {
      final dbDir = await getDatabasesPath();
      dbPath = p.join(dbDir, nomeDb);

      final docsDir = await getApplicationDocumentsDirectory();
      capasDirPath = p.join(docsDir.path, nomePastaCapas);
    }

    return {'db': dbPath, 'capas': capasDirPath};
  }

  Future<void> _fazerBackup() async {
    Navigator.pop(context);
    setState(() => _isLoading = true);

    try {
      final caminhos = await _obterCaminhos();
      final dbPathStr = caminhos['db']!;
      final capasPathStr = caminhos['capas']!;

      final dbFile = io.File(dbPathStr);
      final capasDir = io.Directory(capasPathStr);

      var archive = Archive();

      if (await dbFile.exists()) {
        final dbBytes = await dbFile.readAsBytes();
        final dbFileName = p.basename(dbFile.path);
        archive.addFile(ArchiveFile(dbFileName, dbBytes.length, dbBytes));
      } else {
        throw Exception("Banco de dados não encontrado no disco.");
      }

      if (await capasDir.exists()) {
        final listaItens = capasDir.listSync(recursive: true);

        for (var entity in listaItens) {
          if (entity is io.File) {
            final fileBytes = await entity.readAsBytes();
            if (fileBytes.isNotEmpty) {
              final relPath = p
                  .relative(entity.path, from: capasDir.parent.path)
                  .replaceAll(RegExp(r'[/\\]'), '/');

              archive.addFile(
                ArchiveFile(relPath, fileBytes.length, fileBytes),
              );
            }
          }
        }
      }

      final zipEncoder = ZipEncoder();
      final encodedBytes = zipEncoder.encode(archive);

      if (encodedBytes.isEmpty) {
        throw Exception("Falha ao codificar os dados para o formato ZIP.");
      }

      final bytesZip = Uint8List.fromList(encodedBytes);

      if (bytesZip.length <= 22) {
        throw Exception("O arquivo ZIP gerado está vazio.");
      }

      final String? outputFile = await FilePicker.saveFile(
        dialogTitle: 'Salvar Backup',
        fileName: 'manga_backup.zip',
        bytes: bytesZip,
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );

      if (outputFile != null) {
        final targetFile = io.File(outputFile);
        await targetFile.writeAsBytes(bytesZip);
        _mostrarSnack('Backup salvo com sucesso!', Colors.green);
      }
    } catch (e) {
      _mostrarSnack('Erro ao fazer backup: $e', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _restaurarSubstituindo() async {
    Navigator.pop(context);

    final FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result != null &&
        result.files.isNotEmpty &&
        result.files.single.path != null) {
      setState(() => _isLoading = true);
      try {
        final zipFile = io.File(result.files.single.path!);
        final caminhos = await _obterCaminhos();

        final tempDir = await getTemporaryDirectory();
        final extractPath = p.join(tempDir.path, 'restore_temp');

        final extractDir = io.Directory(extractPath);
        if (extractDir.existsSync()) {
          extractDir.deleteSync(recursive: true);
        }

        await extractFileToDisk(zipFile.path, extractPath);

        final dbName = kDebugMode
            ? 'manga_manager_debug.db'
            : 'manga_manager.db';
        final tempDbFile = io.File(p.join(extractPath, dbName));

        if (tempDbFile.existsSync()) {
          try {
            await DbHelper().closeDatabase();
          } catch (_) {}

          final dbTargetDir = io.File(caminhos['db']!).parent;
          if (!dbTargetDir.existsSync()) {
            dbTargetDir.createSync(recursive: true);
          }

          await tempDbFile.copy(caminhos['db']!);
        } else {
          throw Exception(
            "O arquivo de banco de dados não está presente no ZIP.",
          );
        }

        final nomePastaCapas = kDebugMode
            ? 'manga_manager_capas_debug'
            : 'manga_manager_capas';
        final tempCapasDir = io.Directory(p.join(extractPath, nomePastaCapas));
        final realCapasDir = io.Directory(caminhos['capas']!);

        if (tempCapasDir.existsSync()) {
          if (realCapasDir.existsSync()) {
            await realCapasDir.delete(recursive: true);
          }
          await _copyDirectory(tempCapasDir, realCapasDir);
        }

        _mostrarSnack(
          'Backup restaurado! Substituição completa.',
          Colors.green,
        );

        if (mounted) {
          widget.onBackupRestored();
          globalRefreshController.refresh();
        }
      } catch (e) {
        _mostrarSnack('Erro na restauração: $e', Colors.red);
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _restaurarMesclando() async {
    Navigator.pop(context);

    final FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result != null &&
        result.files.isNotEmpty &&
        result.files.single.path != null) {
      setState(() => _isLoading = true);
      try {
        final zipFile = io.File(result.files.single.path!);
        final caminhos = await _obterCaminhos();

        final tempDir = await getTemporaryDirectory();
        final extractPath = p.join(tempDir.path, 'merge_temp');

        final extractDir = io.Directory(extractPath);
        if (extractDir.existsSync()) {
          extractDir.deleteSync(recursive: true);
        }

        await extractFileToDisk(zipFile.path, extractPath);

        final dbName = kDebugMode
            ? 'manga_manager_debug.db'
            : 'manga_manager.db';
        final tempDbPath = p.join(extractPath, dbName);

        if (!io.File(tempDbPath).existsSync()) {
          throw Exception("Banco de dados não encontrado no ZIP.");
        }

        Database tempDb = await databaseFactory.openDatabase(tempDbPath);
        List<Map<String, dynamic>> tempMangas = await tempDb.query('mangas');
        await tempDb.close();

        Database currentDb = await DbHelper().database;
        int inseridos = 0;

        final nomePastaCapas = kDebugMode
            ? 'manga_manager_capas_debug'
            : 'manga_manager_capas';
        final tempCapasDir = io.Directory(p.join(extractPath, nomePastaCapas));

        for (var manga in tempMangas) {
          final nome = manga['nome_pt'];
          List<Map> existe = await currentDb.query(
            'mangas',
            where: 'nome_pt = ?',
            whereArgs: [nome],
          );

          if (existe.isEmpty) {
            var novoManga = Map<String, dynamic>.from(manga);
            novoManga.remove('id');

            await currentDb.insert('mangas', novoManga);
            inseridos++;

            final capaPath = manga['capa_path'];
            if (capaPath != null &&
                capaPath.toString().isNotEmpty &&
                tempCapasDir.existsSync()) {
              final nomeArquivoCapa = p.basename(capaPath.toString());
              final tempCapaFile = io.File(
                p.join(tempCapasDir.path, nomeArquivoCapa),
              );

              if (tempCapaFile.existsSync()) {
                final realCapasDir = io.Directory(caminhos['capas']!);
                if (!realCapasDir.existsSync()) {
                  realCapasDir.createSync(recursive: true);
                }

                final realCapaDestino = p.join(
                  realCapasDir.path,
                  nomeArquivoCapa,
                );
                await tempCapaFile.copy(realCapaDestino);
              }
            }
          }
        }

        _mostrarSnack(
          'Mesclagem concluída! $inseridos novos registros adicionados.',
          Colors.green,
        );

        if (mounted) {
          widget.onBackupRestored();
          globalRefreshController.refresh();
        }
      } catch (e) {
        _mostrarSnack('Erro ao mesclar: $e', Colors.red);
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _copyDirectory(
    io.Directory source,
    io.Directory destination,
  ) async {
    await destination.create(recursive: true);
    await for (var entity in source.list(recursive: false)) {
      if (entity is io.Directory) {
        var newDirectory = io.Directory(
          p.join(destination.absolute.path, p.basename(entity.path)),
        );
        await newDirectory.create();
        await _copyDirectory(entity.absolute, newDirectory);
      } else if (entity is io.File) {
        await entity.copy(p.join(destination.path, p.basename(entity.path)));
      }
    }
  }

  void _mostrarSnack(String msg, Color cor) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: cor));
  }

  void _abrirMenuOpcoes() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Gerenciador de Backup',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.download, color: Colors.blue),
                  title: const Text('Criar Backup (Exportar .zip)'),
                  subtitle: const Text(
                    'Salva o BD e a pasta de capas num arquivo',
                  ),
                  onTap: _fazerBackup,
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.red,
                  ),
                  title: const Text('Restaurar (Substituir Tudo)'),
                  subtitle: const Text(
                    'Apaga o atual e coloca o do arquivo ZIP',
                  ),
                  onTap: _restaurarSubstituindo,
                ),
                ListTile(
                  leading: const Icon(Icons.merge_type, color: Colors.green),
                  title: const Text('Restaurar (Mesclar / Ignorar Iguais)'),
                  subtitle: const Text(
                    'Mantém o atual e adiciona apenas os nomes diferentes',
                  ),
                  onTap: _restaurarMesclando,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const SizedBox.shrink();
    }

    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        textStyle: const TextStyle(fontSize: 12),
      ),
      icon: _isLoading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.backup, size: 16),
      label: Text(_isLoading ? 'Processando...' : 'Backup / Restaurar'),
      onPressed: _isLoading ? null : _abrirMenuOpcoes,
    );
  }
}
