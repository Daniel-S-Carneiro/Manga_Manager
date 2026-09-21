import 'dart:io' as io;
import 'package:tar/tar.dart';
import 'package:path/path.dart' as p;

class TarStreamHelper {
  /// Retorna um Stream de [TarEntry] lendo os arquivos do banco e das capas via Stream
  static Stream<TarEntry> _buildTarEntries(
    String dbPath,
    String capasDirPath,
  ) async* {
    // 1. Adicionar Banco de Dados
    final dbFile = io.File(dbPath);
    if (dbFile.existsSync()) {
      yield TarEntry(
        TarHeader(
          name: p.basename(dbPath),
          mode: 420, // 0644 em octal (permissão padrão)
          size: dbFile.lengthSync(),
          modified: dbFile.lastModifiedSync(),
        ),
        dbFile.openRead(), // Agora aceita o stream perfeitamente!
      );
    }

    // 2. Adicionar Capas
    final capasDir = io.Directory(capasDirPath);
    if (capasDir.existsSync()) {
      await for (var entity in capasDir.list(recursive: true)) {
        if (entity is io.File) {
          final relPath =
              'capas/${p.relative(entity.path, from: capasDirPath).replaceAll('\\', '/')}';

          yield TarEntry(
            TarHeader(
              name: relPath,
              mode: 420, // 0644 em octal
              size: entity.lengthSync(),
              modified: entity.lastModifiedSync(),
            ),
            entity.openRead(), // Stream direto do disco
          );
        }
      }
    }
  }

  /// Executa a compressão via Streaming (Arquivos -> Tar -> Gzip -> Disco)
  static Future<void> compressToTarGz({
    required String dbPath,
    required String capasDirPath,
    required String tarGzPath,
  }) async {
    final tarGzFile = io.File(tarGzPath);
    final outputSink = tarGzFile.openWrite();

    final tarStream = _buildTarEntries(
      dbPath,
      capasDirPath,
    ).transform(tarWriter);
    final gzipStream = tarStream.transform(io.GZipCodec().encoder);

    await gzipStream.pipe(outputSink);
  }

  /// Executa a extração via Streaming (Disco -> Gzip -> Tar -> Arquivos)
  /// com proteção rigorosa contra Path Traversal.
  static Future<void> extractTarGz({
    required String tarGzPath,
    required String destPath,
  }) async {
    final inputStream = io.File(tarGzPath).openRead();
    final tarStream = inputStream.transform(io.GZipCodec().decoder);
    final reader = TarReader(tarStream);

    final canonicalDest = p.canonicalize(destPath);

    while (await reader.moveNext()) {
      final entry = reader.current;

      if (entry.type == TypeFlag.reg) {
        final targetPath = p.canonicalize(p.join(destPath, entry.name));

        if (!p.isWithin(canonicalDest, targetPath) &&
            targetPath != canonicalDest) {
          throw Exception(
            'Ameaça de Segurança: Tentativa de Path Traversal bloqueada no arquivo: ${entry.name}',
          );
        }

        final outFile = io.File(targetPath);
        outFile.parent.createSync(recursive: true);

        final outSink = outFile.openWrite();
        await entry.contents.pipe(outSink);
      }
    }
  }
}
