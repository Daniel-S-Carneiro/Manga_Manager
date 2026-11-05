import 'dart:io' as io;
import 'dart:math';

import 'package:tar/tar.dart';
import 'package:path/path.dart' as p;

class TarStreamHelper {
  /// Tamanho de cada leitura: o mesmo do `File.openRead()`.
  static const int _pedaco = 64 * 1024;

  /// Lê [arquivo] em pedaços, fechando-o no fim, num erro ou se quem lê
  /// desistir.
  ///
  /// Substitui o `File.openRead()`. Nele, um erro de leitura no meio (arquivo
  /// travado por outro programa, disco com defeito) deixa o arquivo aberto e
  /// o stream nunca termina (no `_FileStream` do Dart SDK, o
  /// `_readInProgress` fica `true` e o `_closeFile` não fecha). Como a
  /// gravação do backup só recebe o erro depois de cancelar a leitura, o
  /// backup ficava parado para sempre.
  ///
  /// Com [tamanho], lê só esses bytes e falha se o arquivo for menor: o tar
  /// grava o tamanho no cabeçalho, antes do conteúdo.
  static Stream<List<int>> lerArquivo(io.File arquivo, {int? tamanho}) async* {
    final aberto = await arquivo.open();
    try {
      var lidos = 0;
      while (tamanho == null || lidos < tamanho) {
        final falta = tamanho == null ? _pedaco : min(_pedaco, tamanho - lidos);
        final pedaco = await aberto.read(falta);
        if (pedaco.isEmpty) break;
        lidos += pedaco.length;
        yield pedaco;
      }
      if (tamanho != null && lidos < tamanho) {
        throw io.FileSystemException(
          'O arquivo diminuiu durante o backup',
          arquivo.path,
        );
      }
    } finally {
      await aberto.close();
    }
  }

  /// Entradas do backup: o banco na raiz e as capas em `capas/`. A lista e
  /// os tamanhos são lidos antes de gravar: um erro aqui (arquivo que sumiu,
  /// sem permissão) acontece antes de criar o arquivo de saída. Um erro
  /// dentro do stream de entradas escaparia do `tarWriter`, que lê esse
  /// stream sem esperar o resultado.
  static List<TarEntry> _entradas(String dbPath, String capasDirPath) {
    TarEntry entrada(String nome, io.File arquivo) {
      final tamanho = arquivo.lengthSync();
      return TarEntry(
        TarHeader(
          name: nome,
          mode: 420, // 0644 em octal (permissão padrão)
          size: tamanho,
          modified: arquivo.lastModifiedSync(),
        ),
        lerArquivo(arquivo, tamanho: tamanho),
      );
    }

    final entradas = <TarEntry>[];
    final dbFile = io.File(dbPath);
    if (dbFile.existsSync()) {
      entradas.add(entrada(p.basename(dbPath), dbFile));
    }

    final capasDir = io.Directory(capasDirPath);
    if (capasDir.existsSync()) {
      for (final entity in capasDir.listSync(recursive: true)) {
        if (entity is io.File) {
          final relPath =
              'capas/${p.relative(entity.path, from: capasDirPath).replaceAll('\\', '/')}';
          entradas.add(entrada(relPath, entity));
        }
      }
    }
    return entradas;
  }

  /// Executa a compressão via Streaming (Arquivos -> Tar -> Gzip -> Disco)
  static Future<void> compressToTarGz({
    required String dbPath,
    required String capasDirPath,
    required String tarGzPath,
  }) async {
    final entradas = _entradas(dbPath, capasDirPath);
    final outputSink = io.File(tarGzPath).openWrite();

    final tarStream = Stream.fromIterable(entradas).transform(tarWriter);
    final gzipStream = tarStream.transform(io.GZipCodec().encoder);

    await gzipStream.pipe(outputSink);
  }

  /// Executa a extração via Streaming (Disco -> Gzip -> Tar -> Arquivos)
  /// com proteção rigorosa contra Path Traversal.
  static Future<void> extractTarGz({
    required String tarGzPath,
    required String destPath,
  }) async {
    final inputStream = lerArquivo(io.File(tarGzPath));
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
