import 'dart:io' as io;
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import '../controllers/refresh_controller.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

const bool _kVerboseMode = false;

void _logDebug(String mensagem) {
  if (_kVerboseMode) {
    debugPrint('[BackupManager] $mensagem');
  }
}

Future<String?> _comprimirTarGzNoIsolate({
  required String dbPath,
  required String capasDirPath,
  required String tarGzOutputPath,
}) async {
  return await Isolate.run(() async {
    try {
      _logDebug(
        '[BackupManager Isolate] Iniciando compressão TAR.GZ via streaming...',
      );

      int totalBytesComprimidos = 0;
      int totalFilesComprimidos = 0;

      final gzFile = io.File(tarGzOutputPath);
      final gzSink = gzFile.openWrite();
      final gzipEncoder = io.GZipCodec().encoder.startChunkedConversion(gzSink);

      List<int> createTarHeader(String name, int size) {
        final header = List<int>.filled(512, 0);

        final nameBytes = utf8.encode(name);
        for (int i = 0; i < nameBytes.length && i < 100; i++) {
          header[i] = nameBytes[i];
        }

        final mode = ascii.encode('0000777\x00');
        for (int i = 0; i < mode.length; i++) {
          header[100 + i] = mode[i];
        }

        final uid = ascii.encode('0000000\x00');
        for (int i = 0; i < uid.length; i++) {
          header[108 + i] = uid[i];
          header[116 + i] = uid[i];
        }

        final sizeOctal = size.toRadixString(8).padLeft(11, '0');
        final sizeField = ascii.encode('$sizeOctal\x00');
        for (int i = 0; i < sizeField.length; i++) {
          header[124 + i] = sizeField[i];
        }

        final mtimeOctal = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final mtimeStr = mtimeOctal.toRadixString(8).padLeft(11, '0');
        final mtimeField = ascii.encode('$mtimeStr\x00');
        for (int i = 0; i < mtimeField.length; i++) {
          header[136 + i] = mtimeField[i];
        }

        header[156] = '0'.codeUnitAt(0);

        final magic = ascii.encode('ustar\x00');
        final version = ascii.encode('00');
        for (int i = 0; i < magic.length; i++) {
          header[257 + i] = magic[i];
        }
        for (int i = 0; i < version.length; i++) {
          header[263 + i] = version[i];
        }

        for (int i = 148; i < 156; i++) {
          header[i] = 0x20;
        }

        final checksumSum = header.fold(0, (a, b) => a + b);
        final checksumOctalStr = checksumSum.toRadixString(8).padLeft(6, '0');
        final checksumField = ascii.encode('$checksumOctalStr\x00 ');

        for (int i = 0; i < checksumField.length; i++) {
          header[148 + i] = checksumField[i];
        }

        return header;
      }

      Future<void> addFileToTarStream(String name, io.File file) async {
        final size = await file.length();
        if (size == 0) return;

        totalFilesComprimidos++;
        totalBytesComprimidos += size;

        final header = createTarHeader(name, size);
        gzipEncoder.add(header);

        await for (final chunk in file.openRead()) {
          gzipEncoder.add(chunk);
        }

        final remainder = size % 512;
        if (remainder > 0) {
          gzipEncoder.add(List<int>.filled(512 - remainder, 0));
        }

        _logDebug('[BackupManager] Streamed: $name ($size bytes)');
      }

      _logDebug('[BackupManager Isolate] Lendo DB via stream...');
      await addFileToTarStream(p.basename(dbPath), io.File(dbPath));

      _logDebug('[BackupManager Isolate] Lendo capas...');
      final capasDir = io.Directory(capasDirPath);
      if (capasDir.existsSync()) {
        for (var entity in capasDir.listSync(recursive: true)) {
          if (entity is io.File) {
            if (p.basename(entity.path).toLowerCase() == 'manifest.json') {
              continue;
            }

            final relPath = p
                .relative(entity.path, from: capasDir.path)
                .replaceAll('\\', '/');

            _logDebug(
              '[BackupManager Isolate] Adicionando capa via stream: $relPath',
            );
            await addFileToTarStream('capas/$relPath', entity);
          }
        }
      }

      _logDebug(
        '[BackupManager Isolate] Criando manifesto temporário no disco...',
      );
      final manifest = {
        'totalFiles': totalFilesComprimidos,
        'totalBytes': totalBytesComprimidos,
      };

      final tempDir = io.Directory.systemTemp;
      final tempManifestFile = io.File(
        p.join(
          tempDir.path,
          'manifest_temp_${DateTime.now().millisecondsSinceEpoch}.json',
        ),
      );

      await tempManifestFile.writeAsString(jsonEncode(manifest));

      try {
        _logDebug('[BackupManager Isolate] Adicionando manifesto ao TAR...');
        await addFileToTarStream('manifest.json', tempManifestFile);
      } finally {
        if (tempManifestFile.existsSync()) {
          tempManifestFile.deleteSync();
          _logDebug(
            '[BackupManager Isolate] Arquivo temporário do manifesto apagado.',
          );
        }
      }

      gzipEncoder.add(List<int>.filled(1024, 0));
      _logDebug(
        '[BackupManager Isolate] Gravado marcador de fim do TAR (1024 nulos).',
      );

      gzipEncoder.close();
      await gzSink.done;

      _logDebug(
        '[BackupManager Isolate] Compressão concluída: $totalFilesComprimidos arquivos, $totalBytesComprimidos bytes.',
      );

      return tarGzOutputPath;
    } catch (e, st) {
      _logDebug('[BackupManager Isolate] ERRO NA COMPRESSÃO: $e\n$st');
      return null;
    }
  });
}

class TarHeader {
  final String name;
  final int size;
  final bool isFile;
  TarHeader(this.name, this.size, this.isFile);
}

TarHeader? parseTarHeader(List<int> block) {
  if (block.length < 512) return null;

  final nameBytes = block.sublist(0, 100);
  final name = String.fromCharCodes(nameBytes).replaceAll('\x00', '').trim();
  if (name.isEmpty) return null;

  final sizeField = String.fromCharCodes(
    block.sublist(124, 136),
  ).replaceAll('\x00', '').trim();
  _logDebug('[PARSE] sizeField="$sizeField"');
  _logDebug('[PARSE] size=${int.tryParse(sizeField, radix: 8)}');
  _logDebug('[PARSE] raw=${block.sublist(124, 136)}');

  final size = int.tryParse(sizeField, radix: 8) ?? 0;
  final typeFlag = block[156];
  final isFile = typeFlag == 48;

  return TarHeader(name, size, isFile);
}

Future<bool> _extrairTarGzNoIsolate(
  String tarGzFilePath,
  String destinoPath,
) async {
  return await Isolate.run(() async {
    try {
      _logDebug(
        '[BackupManager Isolate] Extraindo TAR.GZ via streaming otimizado...',
      );

      final inputStream = io.File(tarGzFilePath).openRead();
      final tarStream = inputStream.transform(io.GZipCodec().decoder);

      final buffer = BytesBuilder(copy: false);
      int totalBytes = 0;
      int totalFiles = 0;

      TarHeader? currentHeader;
      io.IOSink? currentSink;

      int remainingBytes = 0;
      int paddingRemaining = 0;

      await for (final chunk in tarStream) {
        buffer.add(chunk);

        final data = buffer.takeBytes();
        int offset = 0;

        while (offset < data.length) {
          int available = data.length - offset;

          if (remainingBytes > 0) {
            final toRead = remainingBytes < available
                ? remainingBytes
                : available;

            currentSink!.add(data.sublist(offset, offset + toRead));

            offset += toRead;
            remainingBytes -= toRead;

            if (remainingBytes == 0) {
              await currentSink.flush();
              await currentSink.close();
              _logDebug('[STREAM EXTRACT] FECHOU ${currentHeader?.name}');
              currentSink = null;
              currentHeader = null;
            }
            continue;
          }

          if (paddingRemaining > 0) {
            final toSkip = paddingRemaining < available
                ? paddingRemaining
                : available;

            offset += toSkip;
            paddingRemaining -= toSkip;
            continue;
          }

          if (available < 512) {
            break;
          }

          final block = data.sublist(offset, offset + 512);
          offset += 512;

          final header = parseTarHeader(block);

          if (header == null) {
            _logDebug('[BackupManager Isolate] Fim do arquivo TAR alcançado.');
            return true;
          }

          if (header.isFile) {
            totalFiles++;
            totalBytes += header.size;

            final filePath = p.join(destinoPath, header.name);
            final outFile = io.File(filePath);
            outFile.parent.createSync(recursive: true);

            currentHeader = header;
            currentSink = outFile.openWrite();
            remainingBytes = header.size;
            paddingRemaining = (512 - (header.size % 512)) % 512;
          } else {
            io.Directory(
              p.join(destinoPath, header.name),
            ).createSync(recursive: true);
          }
        }

        if (offset < data.length) {
          buffer.add(data.sublist(offset));
        }
      }

      _logDebug(
        '[BackupManager Isolate] Extração concluída: $totalFiles arquivos, $totalBytes bytes no total.',
      );
      return true;
    } catch (e, st) {
      _logDebug('[BackupManager Isolate] ERRO NA EXTRAÇÃO STREAMING: $e\n$st');
      return false;
    }
  });
}

class BackupManagerButton extends StatefulWidget {
  final VoidCallback onBackupRestored;

  const BackupManagerButton({super.key, required this.onBackupRestored});

  @override
  State<BackupManagerButton> createState() => _BackupManagerButtonState();
}

class _BackupManagerButtonState extends State<BackupManagerButton> {
  bool _isLoading = false;

  static const String _dbName = kDebugMode
      ? 'manga_manager_debug.db'
      : 'manga_manager.db';
  static const String _nomePastaCapas = kDebugMode
      ? 'manga_manager_capas_debug'
      : 'manga_manager_capas';

  Future<Map<String, String>> _obterCaminhos() async {
    String dbPath;
    String capasDirPath;

    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      final directory = await getApplicationSupportDirectory();
      dbPath = p.join(directory.path, _dbName);

      final docsDir = await getApplicationDocumentsDirectory();
      capasDirPath = p.join(docsDir.path, _nomePastaCapas);
    } else {
      final dbDir = await getDatabasesPath();
      dbPath = p.join(dbDir, _dbName);

      final docsDir = await getApplicationDocumentsDirectory();
      capasDirPath = p.join(docsDir.path, _nomePastaCapas);
    }

    return {'db': dbPath, 'capas': capasDirPath};
  }

  void _mostrarFeedback(String msg, {bool isError = false}) {
    if (!mounted) return;
    _logDebug(isError ? 'ERRO: $msg' : 'SUCESSO: $msg');

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _limparDiretorio(String? path) {
    if (path == null) return;
    final dir = io.Directory(path);
    if (dir.existsSync()) {
      try {
        dir.deleteSync(recursive: true);
        _logDebug('Diretório limpo: $path');
      } catch (e) {
        _logDebug('Aviso: Falha ao limpar diretório $path: $e');
      }
    }
  }

  void _limparArquivo(String? path) {
    if (path == null) return;
    final file = io.File(path);
    if (file.existsSync()) {
      try {
        file.deleteSync();
        _logDebug('Arquivo temporário removido: $path');
      } catch (e) {
        _logDebug('Aviso: Falha ao remover arquivo $path: $e');
      }
    }
  }

  Future<void> _fazerBackup() async {
    Navigator.pop(context);
    setState(() => _isLoading = true);
    String? tempTarGzPath;

    try {
      _logDebug('Iniciando processo de backup...');
      final caminhos = await _obterCaminhos();

      final arquivoDb = io.File(caminhos['db']!);
      if (!arquivoDb.existsSync()) {
        throw Exception("Banco de dados principal não encontrado.");
      }

      _logDebug('Fechando BD temporariamente para o backup...');
      await DbHelper().closeDatabase();

      final tempDir = await getTemporaryDirectory();
      tempTarGzPath = p.join(
        tempDir.path,
        'manga_backup_${DateTime.now().millisecondsSinceEpoch}.tar.gz',
      );

      _logDebug('Executando compressão nativa via Isolate...');

      final resultadoPath = await _comprimirTarGzNoIsolate(
        dbPath: caminhos['db']!,
        capasDirPath: caminhos['capas']!,
        tarGzOutputPath: tempTarGzPath,
      );

      if (resultadoPath == null || !(await io.File(resultadoPath).exists())) {
        throw Exception("Falha interna ao gerar o pacote .tar.gz.");
      }

      _logDebug('Solicitando local de salvamento ao usuário...');
      final String? outputFile = await FilePicker.saveFile(
        dialogTitle: 'Salvar Backup',
        fileName: 'manga_backup.tar.gz',
        type: FileType.custom,
        allowedExtensions: ['gz', 'tar'],
      );

      if (outputFile != null) {
        String pathFinal = outputFile;
        if (!pathFinal.toLowerCase().endsWith('.tar.gz')) {
          pathFinal = '$pathFinal.tar.gz';
        }

        await io.File(resultadoPath).copy(pathFinal);
        _mostrarFeedback('Backup exportado com sucesso!');
      } else {
        _logDebug('Usuário cancelou o salvamento do arquivo.');
      }
    } catch (e) {
      _mostrarFeedback(
        e.toString().replaceAll('Exception: ', ''),
        isError: true,
      );
    } finally {
      _limparArquivo(tempTarGzPath);
      await DbHelper().database;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _restaurarSubstituindo() async {
    Navigator.pop(context);

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gz', 'tar'],
    );
    if (result == null ||
        result.files.isEmpty ||
        result.files.single.path == null) {
      return;
    }

    setState(() => _isLoading = true);
    String? pastaTemporaria;

    try {
      _logDebug('Iniciando restauração completa (Substituição)...');
      final tarGzFilePath = result.files.single.path!;
      final caminhos = await _obterCaminhos();
      final tempDir = await getTemporaryDirectory();
      pastaTemporaria = p.join(
        tempDir.path,
        'restore_${DateTime.now().millisecondsSinceEpoch}',
      );

      final sucessoExtraicao = await _extrairTarGzNoIsolate(
        tarGzFilePath,
        pastaTemporaria,
      );
      if (!sucessoExtraicao) {
        throw Exception("Falha ao descompactar o arquivo .tar.gz.");
      }

      final tempDbFile = io.File(p.join(pastaTemporaria, _dbName));
      io.File? encontradoDb = tempDbFile.existsSync() ? tempDbFile : null;

      if (encontradoDb == null) {
        try {
          for (var entidade in io.Directory(
            pastaTemporaria,
          ).listSync(recursive: true)) {
            if (entidade is io.File &&
                p.basename(entidade.path).toLowerCase() ==
                    _dbName.toLowerCase()) {
              encontradoDb = entidade;
              break;
            }
          }
        } catch (_) {}
      }

      if (encontradoDb == null || !encontradoDb.existsSync()) {
        throw Exception("Arquivo de banco de dados ausente no backup.");
      }

      _logDebug('Fechando e substituindo Banco de Dados...');
      try {
        await DbHelper().closeDatabase();
      } catch (_) {}

      final dbTargetDir = io.File(caminhos['db']!).parent;
      if (!dbTargetDir.existsSync()) {
        dbTargetDir.createSync(recursive: true);
      }

      await encontradoDb.copy(caminhos['db']!);

      _logDebug('Substituindo pasta de Capas...');
      final realCapasDir = io.Directory(caminhos['capas']!);
      if (realCapasDir.existsSync()) {
        try {
          realCapasDir.deleteSync(recursive: true);
        } catch (_) {}
      }
      realCapasDir.createSync(recursive: true);

      final pastaTempDir = io.Directory(pastaTemporaria);
      int capasCopiadas = 0;

      if (pastaTempDir.existsSync()) {
        final entidades = pastaTempDir.listSync(recursive: true);
        for (var entidade in entidades) {
          if (entidade is io.File) {
            final nomeArquivo = p.basename(entidade.path);
            if (nomeArquivo.toLowerCase() == _dbName.toLowerCase()) {
              continue;
            }

            final caminhoRelativo = p.relative(
              entidade.path,
              from: pastaTemporaria,
            );
            List<String> partes = p.split(caminhoRelativo);

            partes.removeWhere(
              (p) =>
                  p.startsWith('manga_backup_staging_') ||
                  p.startsWith('restore_'),
            );

            if (partes.isNotEmpty &&
                (partes.first.toLowerCase() == 'capas' ||
                    partes.first.toLowerCase() ==
                        _nomePastaCapas.toLowerCase())) {
              partes.removeAt(0);
            }

            final destinoPath = partes.isNotEmpty
                ? p.joinAll([realCapasDir.path, ...partes])
                : p.join(realCapasDir.path, nomeArquivo);

            final destinoArquivo = io.File(destinoPath);
            destinoArquivo.parent.createSync(recursive: true);
            entidade.copySync(destinoArquivo.path);
            capasCopiadas++;
          }
        }
      }

      _mostrarFeedback('Backup restaurado com sucesso! ($capasCopiadas capas)');
      if (mounted) _atualizarInterface();
    } catch (e, st) {
      _logDebug('ERRO NA RESTAURAÇÃO: $e\n$st');
      _mostrarFeedback(
        e.toString().replaceAll('Exception: ', ''),
        isError: true,
      );
    } finally {
      _limparDiretorio(pastaTemporaria);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _restaurarMesclando() async {
    Navigator.pop(context);

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gz', 'tar'],
    );
    if (result == null ||
        result.files.isEmpty ||
        result.files.single.path == null) {
      return;
    }

    setState(() => _isLoading = true);
    String? pastaTemporaria;

    try {
      _logDebug('Iniciando restauração (Mesclagem)...');
      final tarGzFilePath = result.files.single.path!;
      final caminhos = await _obterCaminhos();
      final tempDir = await getTemporaryDirectory();
      pastaTemporaria = p.join(
        tempDir.path,
        'merge_${DateTime.now().millisecondsSinceEpoch}',
      );

      final sucessoExtraicao = await _extrairTarGzNoIsolate(
        tarGzFilePath,
        pastaTemporaria,
      );
      if (!sucessoExtraicao) {
        throw Exception("Falha ao descompactar o arquivo .tar.gz.");
      }

      io.File? encontradoDb;
      try {
        for (var entidade in io.Directory(
          pastaTemporaria,
        ).listSync(recursive: true)) {
          if (entidade is io.File &&
              p.basename(entidade.path).toLowerCase() ==
                  _dbName.toLowerCase()) {
            encontradoDb = entidade;
            break;
          }
        }
      } catch (_) {}

      if (encontradoDb == null || !encontradoDb.existsSync()) {
        throw Exception("Banco de dados não encontrado no pacote.");
      }

      _logDebug('Processando registros do banco de dados...');
      Database tempDb = await databaseFactory.openDatabase(encontradoDb.path);
      List<Map<String, dynamic>> tempMangas = await tempDb.query('mangas');
      await tempDb.close();

      Database currentDb = await DbHelper().database;
      int inseridos = 0;
      final realCapasDir = io.Directory(caminhos['capas']!);

      Map<String, io.File> mapaCapas = {};
      for (var entidade in io.Directory(
        pastaTemporaria,
      ).listSync(recursive: true)) {
        if (entidade is io.File) {
          mapaCapas[p.basename(entidade.path).toLowerCase()] = entidade;
        }
      }

      for (var manga in tempMangas) {
        List<Map> existe = await currentDb.query(
          'mangas',
          where: 'nome_pt = ?',
          whereArgs: [manga['nome_pt']],
        );

        if (existe.isEmpty) {
          var novoManga = Map<String, dynamic>.from(manga)..remove('id');
          await currentDb.insert('mangas', novoManga);
          inseridos++;

          final capaPath = manga['capa_path'];
          if (capaPath != null && capaPath.toString().isNotEmpty) {
            final nomeArquivoCapa = p.basename(capaPath.toString());

            io.File? arquivoCapaReal = mapaCapas[nomeArquivoCapa.toLowerCase()];

            if (arquivoCapaReal != null && arquivoCapaReal.existsSync()) {
              if (!realCapasDir.existsSync()) {
                realCapasDir.createSync(recursive: true);
              }
              await arquivoCapaReal.copy(
                p.join(realCapasDir.path, nomeArquivoCapa),
              );
            }
          }
        }
      }

      _mostrarFeedback('Mesclagem finalizada: $inseridos novos mangás.');
      if (mounted) _atualizarInterface();
    } catch (e, st) {
      _logDebug('ERRO NA MESCLAGEM: $e\n$st');
      _mostrarFeedback(
        e.toString().replaceAll('Exception: ', ''),
        isError: true,
      );
    } finally {
      _limparDiretorio(pastaTemporaria);
      setState(() => _isLoading = false);
    }
  }

  void _atualizarInterface() {
    imageCache.clear();
    imageCache.clearLiveImages();
    widget.onBackupRestored();
    globalRefreshController.refresh();
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
                  title: const Text('Criar Backup (Exportar .tar.gz)'),
                  subtitle: const Text(
                    'Salva o BD e a pasta de capas num arquivo comprimido',
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
                    'Apaga o atual e coloca o do arquivo .tar.gz',
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
    if (kIsWeb) return const SizedBox.shrink();

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
