import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';
import 'dart:typed_data';

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

    final tarStream = Stream.fromIterable([
      _manifesto(entradas),
      ...entradas,
    ]).transform(tarWriter);
    final gzipStream = tarStream.transform(io.GZipCodec().encoder);

    await gzipStream.pipe(outputSink);
  }

  // ==========================================
  // MANIFESTO
  // ==========================================

  /// Lista dos arquivos do backup com o tamanho de cada um, gravada como
  /// **primeira** entrada (a lista já é conhecida antes de gravar). Na
  /// restauração, um backup cortado (download incompleto, pendrive removido)
  /// falha antes de mexer nos dados, mesmo que o corte caia exatamente entre
  /// dois arquivos, caso que o tar e o gzip sozinhos não percebem.
  static const String nomeManifesto = 'manifesto.json';

  /// Manifesto de depuração de uma versão de setembro de 2026, que só contava
  /// os arquivos: é ignorado (antes virava uma "capa" ao substituir tudo).
  static const String _manifestoAntigo = 'manifest.json';

  static const int _formatoManifesto = 1;

  /// Limite para ler o manifesto na memória (com milhares de capas ele ainda
  /// fica em centenas de KB).
  static const int _tamanhoMaximoManifesto = 8 * 1024 * 1024;

  static TarEntry _manifesto(List<TarEntry> entradas) {
    final conteudo = utf8.encode(
      jsonEncode({
        'formato': _formatoManifesto,
        'arquivos': {for (final e in entradas) e.header.name: e.header.size},
      }),
    );
    return TarEntry.data(
      TarHeader(
        name: nomeManifesto,
        mode: 420,
        size: conteudo.length,
        modified: DateTime.now(),
      ),
      conteudo,
    );
  }

  static Future<Map<String, int>> _lerManifesto(TarEntry entry) async {
    if (entry.size > _tamanhoMaximoManifesto) {
      throw const FormatException('Manifesto do backup grande demais');
    }
    final bytes = BytesBuilder(copy: false);
    await entry.contents.forEach(bytes.add);
    final dados = jsonDecode(utf8.decode(bytes.takeBytes()));
    if (dados is! Map || dados['arquivos'] is! Map) {
      throw const FormatException('Manifesto do backup inválido');
    }
    return {
      for (final MapEntry(:key, :value) in (dados['arquivos'] as Map).entries)
        key as String: (value as num).toInt(),
    };
  }

  /// Arquivos do [manifesto] que não vieram no backup ([extraidos]: nome →
  /// tamanho) ou vieram com outro tamanho.
  static List<String> conferirManifesto(
    Map<String, int> manifesto,
    Map<String, int> extraidos,
  ) => [
    for (final MapEntry(key: nome, value: tamanho) in manifesto.entries)
      if (extraidos[nome] != tamanho) nome,
  ];

  /// Executa a extração via Streaming (Disco -> Gzip -> Tar -> Arquivos)
  /// com proteção rigorosa contra Path Traversal. Se o backup tiver
  /// manifesto, confere no fim que todos os arquivos dele vieram inteiros e,
  /// se não, lança [BackupIncompleto]. Backups sem manifesto (feitos antes
  /// da v2.2.1) são aceitos como antes.
  static Future<void> extractTarGz({
    required String tarGzPath,
    required String destPath,
  }) async {
    final inputStream = lerArquivo(io.File(tarGzPath));
    final tarStream = inputStream.transform(io.GZipCodec().decoder);
    final reader = TarReader(tarStream);

    final canonicalDest = p.canonicalize(destPath);
    Map<String, int>? manifesto;
    final extraidos = <String, int>{};

    while (await reader.moveNext()) {
      final entry = reader.current;

      if (entry.type == TypeFlag.reg) {
        if (entry.name == nomeManifesto) {
          manifesto = await _lerManifesto(entry);
          continue;
        }
        if (entry.name == _manifestoAntigo) continue;

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
        extraidos[entry.name] = entry.size;
      }
    }

    if (manifesto != null) {
      final problemas = conferirManifesto(manifesto, extraidos);
      if (problemas.isNotEmpty) {
        throw BackupIncompleto(problemas, total: manifesto.length);
      }
    }
  }
}

/// O backup não trouxe todos os arquivos do manifesto, ou trouxe algum com
/// outro tamanho.
class BackupIncompleto implements Exception {
  BackupIncompleto(this.arquivos, {required this.total});

  /// Arquivos que faltaram ou vieram com outro tamanho.
  final List<String> arquivos;
  final int total;

  /// Mensagem para o usuário: a restauração para antes de mexer nos dados.
  String get mensagem {
    final exemplos = arquivos.take(3).join(', ');
    final mais = arquivos.length > 3 ? '…' : '';
    return 'O backup está incompleto: ${arquivos.length} de $total arquivos '
        'faltando ou danificados ($exemplos$mais). Nada foi alterado.';
  }

  @override
  String toString() => mensagem;
}
