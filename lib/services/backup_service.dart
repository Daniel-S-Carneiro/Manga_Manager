import 'dart:io' as io;
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/db_helper.dart';
import '../utils/tar_stream_helper.dart';
import 'update_service.dart';

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
  /// Extrai o backup. Devolve `null` se deu certo, ou a mensagem de erro
  /// para o usuário.
  static Future<String?> _extractIsolate(Map<String, String> args) async {
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
      return null;
    } on BackupIncompleto catch (e) {
      _logDebug('BACKUP INCOMPLETO: ${e.arquivos}');
      return e.mensagem;
    } catch (e, st) {
      _logDebug('ERRO NA EXTRAÇÃO STREAMING: $e\n$st');
      return 'Falha ao descompactar o arquivo .tar.gz. Verifique se o arquivo '
          'não está corrompido.';
    }
  }

  /// O banco dentro do backup. Prefere o do modo atual, mas aceita o do outro:
  /// um backup do app instalado (`onde_parei.db`) também restaura no debug,
  /// e o contrário também. Por último, aceita o banco do app quando ele se
  /// chamava Manga Manager (`manga_manager.db`), que é como a biblioteca
  /// passa para o app com o nome novo.
  static io.File? bancoDoBackup(List<io.File> arquivos, {required bool debug}) {
    final preferidos = debug
        ? [
            DbHelper.nomeBancoDebug,
            DbHelper.nomeBancoRelease,
            DbHelper.nomeBancoDebugAntigo,
            DbHelper.nomeBancoReleaseAntigo,
          ]
        : [
            DbHelper.nomeBancoRelease,
            DbHelper.nomeBancoDebug,
            DbHelper.nomeBancoReleaseAntigo,
            DbHelper.nomeBancoDebugAntigo,
          ];
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
  /// Gera o backup (.tar.gz) direto em [destino]. Se falhar no meio, apaga o
  /// arquivo pela metade.
  Future<String> exportBackup(String destino) async {
    final dbHelper = DbHelper();
    dbHelper.lockDatabase();
    var gravacaoIniciada = false;
    var concluido = false;

    try {
      final dbPath = await dbHelper.getDatabasePathString();
      final capasDir = await dbHelper.getCapasDirectory();

      await dbHelper.closeDatabase();

      gravacaoIniciada = true;
      final resultPath = await Isolate.run(
        () => _compressIsolate({
          'dbPath': dbPath,
          'capasDirPath': capasDir.path,
          'tarGzPath': destino,
        }),
      );

      if (resultPath == null || !io.File(resultPath).existsSync()) {
        throw Exception(
          "Falha ao gerar o arquivo de backup compactado. Verifique os logs.",
        );
      }

      concluido = true;
      return destino;
    } finally {
      if (gravacaoIniciada && !concluido) {
        await _apagarArquivoPelaMetade(io.File(destino));
      }
      await dbHelper.reopenDatabase();
      dbHelper.unlockDatabase();
    }
  }

  /// Apaga o backup que falhou no meio. Num erro, o Dart fecha o arquivo sem
  /// esperar o fechamento terminar, e no Windows um arquivo aberto não pode
  /// ser apagado: por isso tenta algumas vezes.
  static Future<void> _apagarArquivoPelaMetade(io.File arquivo) async {
    for (var tentativa = 1; tentativa <= 5; tentativa++) {
      try {
        if (arquivo.existsSync()) arquivo.deleteSync();
        return;
      } on io.FileSystemException catch (e) {
        if (tentativa == 5) {
          _logDebug('Não deu para apagar o backup pela metade: $e');
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
  }

  Future<String> restoreBackup(
    String tarGzFilePath, {
    required bool merge,
  }) async {
    final quantidade = await _restaurar(
      merge: merge,
      prefixo: 'restore',
      // Tudo é conferido aqui, numa pasta temporária, antes de mexer nos
      // dados: um backup com problema para a restauração neste ponto
      preparar: (destPath) async {
        final erro = await Isolate.run(
          () => _extractIsolate({
            'tarGzPath': tarGzFilePath,
            'destPath': destPath,
          }),
        );
        if (erro != null) throw Exception(erro);
      },
    );
    return merge
        ? 'Mesclagem concluída: $quantidade novos itens inseridos.'
        : 'Backup substituído e restaurado com sucesso!';
  }

  /// Traz a biblioteca do Manga Manager (o app quando tinha o nome antigo)
  /// instalado neste computador, a partir do [banco] dele. Funciona como a
  /// restauração de um backup: [merge] acrescenta só as leituras que faltam;
  /// sem ele, o banco daqui (leituras, capas e configurações) é trocado pelo
  /// do Manga Manager. O banco e as capas do Manga Manager só são lidos.
  Future<String> importarDoMangaManager(
    io.File banco, {
    required bool merge,
  }) async {
    final quantidade = await _restaurar(
      merge: merge,
      prefixo: 'importar',
      preparar: (destPath) => _copiarDoMangaManager(banco, destPath),
    );
    if (merge) {
      return quantidade == 1
          ? 'Importação concluída: 1 leitura nova do Manga Manager.'
          : 'Importação concluída: $quantidade leituras novas do Manga '
                'Manager.';
    }
    return quantidade == 1
        ? 'Biblioteca do Manga Manager importada: 1 leitura.'
        : 'Biblioteca do Manga Manager importada: $quantidade leituras.';
  }

  /// Monta, em [destPath], o que a restauração de um backup encontra depois
  /// de extrair o arquivo: uma cópia do [banco] do Manga Manager e as capas
  /// que ele usa, em `capas/`.
  static Future<void> _copiarDoMangaManager(
    io.File banco,
    String destPath,
  ) async {
    if (!banco.existsSync()) {
      throw Exception('O banco do Manga Manager não foi encontrado.');
    }
    final pasta = io.Directory(destPath)..createSync(recursive: true);
    final copia = p.join(pasta.path, p.basename(banco.path));
    await banco.copy(copia);
    // Uma gravação que o Manga Manager deixou pela metade fica no diário: ele
    // vai junto, e o SQLite completa ou desfaz a gravação ao abrir a cópia
    for (final sufixo in ['-journal', '-wal']) {
      final diario = io.File('${banco.path}$sufixo');
      if (diario.existsSync()) await diario.copy('$copia$sufixo');
    }

    final db = await openDatabase(copia);
    try {
      final pastaCapas = io.Directory(p.join(pasta.path, 'capas'))
        ..createSync();
      final linhas = await db.query('mangas', columns: ['capa_path']);
      // O banco guarda o caminho completo das capas neste computador
      for (final linha in linhas) {
        final caminho = linha['capa_path'] as String?;
        if (caminho == null || caminho.isEmpty) continue;
        final capa = io.File(caminho);
        final destino = io.File(
          p.join(pastaCapas.path, DbHelper.nomeDoArquivo(caminho)),
        );
        if (capa.existsSync() && !destino.existsSync()) {
          await capa.copy(destino.path);
        }
      }
    } finally {
      await db.close();
    }
  }

  /// Restauração: [preparar] põe numa pasta temporária o banco e as capas
  /// (extraídos de um backup ou copiados do Manga Manager). Devolve quantas
  /// leituras entraram ([merge]) ou quantas ficaram no banco.
  Future<int> _restaurar({
    required bool merge,
    required String prefixo,
    required Future<void> Function(String destPath) preparar,
  }) async {
    final dbHelper = DbHelper();
    dbHelper.lockDatabase();
    io.Directory? extraidoDir;

    try {
      final tempDir = await getTemporaryDirectory();
      final destPath = p.join(
        tempDir.path,
        '${prefixo}_${DateTime.now().millisecondsSinceEpoch}',
      );
      extraidoDir = io.Directory(destPath);

      await preparar(destPath);

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
        return await dbHelper.mergeFromBackup(dbExtraido.path, extraidoDir);
      } else {
        // A versão do app que roda aqui fica, e não a do banco que chega: com
        // a de outro aparelho (um backup do Manga Manager traz a v2.2.2), a
        // próxima abertura avisaria "Onde Parei atualizado"
        final versaoDaqui = await _lerConfig(UpdateService.kVersaoApp);
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

        await _gravarConfig(UpdateService.kVersaoApp, versaoDaqui);
        final db = await dbHelper.bancoEmManutencao();
        final total = await db.rawQuery('SELECT COUNT(*) AS n FROM mangas');
        return total.first['n'] as int;
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

  /// Uma configuração lida com o banco travado (restauração em andamento).
  static Future<String?> _lerConfig(String chave) async {
    final db = await DbHelper().bancoEmManutencao();
    final linhas = await db.query(
      'configuracoes',
      columns: ['valor'],
      where: 'chave = ?',
      whereArgs: [chave],
    );
    return linhas.isEmpty ? null : linhas.first['valor'] as String?;
  }

  /// Grava (ou apaga, com [valor] nulo) uma configuração com o banco travado.
  static Future<void> _gravarConfig(String chave, String? valor) async {
    final db = await DbHelper().bancoEmManutencao();
    if (valor == null) {
      await db.delete('configuracoes', where: 'chave = ?', whereArgs: [chave]);
    } else {
      await db.insert('configuracoes', {
        'chave': chave,
        'valor': valor,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
}
