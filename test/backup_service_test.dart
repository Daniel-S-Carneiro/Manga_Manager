// Falha rápido se alguma chamada ficar sem resposta
@Timeout(Duration(seconds: 60))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onde_parei/database/db_helper.dart';
import 'package:onde_parei/services/backup_service.dart';
import 'package:onde_parei/utils/tar_stream_helper.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tar/tar.dart';

import 'apoio/banco_de_teste.dart';

void main() {
  late Directory raiz;

  setUpAll(iniciarSqfliteDeTeste);
  setUp(() async => raiz = await prepararBancoDeTeste('backup_teste'));
  tearDown(() => encerrarBancoDeTeste(raiz));

  /// Backup como o que o app do Windows gera: o banco do app instalado com o
  /// caminho das capas no Windows, e a pasta `capas/`. O [nomeDoBanco]
  /// padrão é o de hoje; com `manga_manager.db` é o backup do app quando ele
  /// se chamava Manga Manager (as capas ficavam em `manga_manager_capas`).
  Future<String> backupDoWindows({
    String nomeDoBanco = DbHelper.nomeBancoRelease,
  }) async {
    final origem = Directory(p.join(raiz.path, 'origem'))..createSync();
    final capas = Directory(p.join(origem.path, 'capas'))..createSync();
    File(p.join(capas.path, 'capa_1.jpg')).writeAsBytesSync([1, 2, 3]);
    File(p.join(capas.path, 'Capa_2.PNG')).writeAsBytesSync([4, 5, 6]);

    final dbPath = p.join(origem.path, nomeDoBanco);
    final db = await openDatabase(dbPath);
    await db.execute('''
      CREATE TABLE mangas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome_pt TEXT NOT NULL,
        nome_en TEXT,
        capitulo INTEGER NOT NULL DEFAULT 1,
        link_url TEXT,
        capa_path TEXT,
        status_leitura TEXT DEFAULT 'Lendo',
        ordem_leitura INTEGER DEFAULT 0
      )''');
    await db.execute(
      'CREATE TABLE configuracoes (chave TEXT PRIMARY KEY, valor TEXT)',
    );
    const pastaWindows = r'C:\Users\dscda\Documents\manga_manager_capas';
    await db.insert('mangas', {
      'nome_pt': 'Com capa',
      'capa_path': '$pastaWindows/capa_1.jpg',
    });
    await db.insert('mangas', {
      'nome_pt': 'Capa com barra invertida',
      'capa_path': '$pastaWindows\\capa_2.png',
    });
    await db.insert('mangas', {
      'nome_pt': 'Capa genérica',
      'capa_path': 'assets/capa_generica.png',
    });
    await db.close();

    final tarGz = p.join(raiz.path, 'onde_parei_backup.tar.gz');
    await TarStreamHelper.compressToTarGz(
      dbPath: dbPath,
      capasDirPath: capas.path,
      tarGzPath: tarGz,
    );
    return tarGz;
  }

  Future<Map<String, String?>> capasNoBanco() async {
    final db = await openDatabase(await DbHelper().getDatabasePathString());
    final linhas = await db.query('mangas', orderBy: 'nome_pt');
    await db.close();
    return {
      for (final l in linhas) l['nome_pt'] as String: l['capa_path'] as String?,
    };
  }

  test(
    'substituir: backup do Windows (app instalado) restaura no debug',
    () async {
      final backup = await backupDoWindows();

      final mensagem = await BackupService().restoreBackup(
        backup,
        merge: false,
      );
      expect(mensagem, contains('sucesso'));

      final pastaCapas = (await DbHelper().getCapasDirectory()).path;
      final capas = await capasNoBanco();
      expect(capas['Com capa'], p.join(pastaCapas, 'capa_1.jpg'));
      // Barra invertida e maiúsculas diferentes no banco e no arquivo (no
      // Windows a extração ainda passa o nome para minúsculas)
      final invertida = capas['Capa com barra invertida']!;
      expect(p.dirname(invertida), pastaCapas);
      expect(p.basename(invertida).toLowerCase(), 'capa_2.png');
      expect(File(invertida).existsSync(), isTrue);
      expect(capas['Capa genérica'], 'assets/capa_generica.png');
      expect(File(capas['Com capa']!).readAsBytesSync(), [1, 2, 3]);
      // O banco do backup não vira "capa"
      expect(
        File(p.join(pastaCapas, DbHelper.nomeBancoRelease)).existsSync(),
        isFalse,
      );
    },
  );

  group('backup do Manga Manager (nome antigo do app)', () {
    test(
      'substituir: o banco antigo vira o banco daqui, com capas e tipo',
      () async {
        final backup = await backupDoWindows(
          nomeDoBanco: DbHelper.nomeBancoReleaseAntigo,
        );

        final mensagem = await BackupService().restoreBackup(
          backup,
          merge: false,
        );
        expect(mensagem, contains('sucesso'));

        final linhas = await DbHelper().getMangas();
        expect(linhas.map((l) => l['nome_pt']), hasLength(3));
        expect(linhas.map((l) => l['tipo']), everyElement(isNull));

        final pastaCapas = (await DbHelper().getCapasDirectory()).path;
        final comCapa = linhas.firstWhere((l) => l['nome_pt'] == 'Com capa');
        expect(comCapa['capa_path'], p.join(pastaCapas, 'capa_1.jpg'));
        expect(File(comCapa['capa_path'] as String).existsSync(), isTrue);
        // O banco antigo não vira "capa"
        expect(
          File(
            p.join(pastaCapas, DbHelper.nomeBancoReleaseAntigo),
          ).existsSync(),
          isFalse,
        );
      },
    );

    test('mesclar: insere os itens do banco antigo', () async {
      final backup = await backupDoWindows(
        nomeDoBanco: DbHelper.nomeBancoReleaseAntigo,
      );
      final mensagem = await BackupService().restoreBackup(backup, merge: true);
      expect(mensagem, contains('3 novos'));
    });
  });

  test('mesclar: insere os mangás com as capas apontando para cá', () async {
    final backup = await backupDoWindows();

    final mensagem = await BackupService().restoreBackup(backup, merge: true);
    expect(mensagem, contains('3 novos'));

    final pastaCapas = (await DbHelper().getCapasDirectory()).path;
    final capas = await capasNoBanco();
    expect(capas['Com capa'], p.join(pastaCapas, 'capa_1.jpg'));
    expect(File(capas['Com capa']!).existsSync(), isTrue);
    expect(capas['Capa genérica'], 'assets/capa_generica.png');

    // Mesclar de novo não duplica
    final deNovo = await BackupService().restoreBackup(backup, merge: true);
    expect(deNovo, contains('0 novos'));
  });

  /// Backup de uma versão nova do app: banco com a coluna `tipo` e uma
  /// coluna que esta versão ainda não conhece.
  Future<String> backupComTipo() async {
    final origem = Directory(p.join(raiz.path, 'origem_nova'))..createSync();
    final capas = Directory(p.join(origem.path, 'capas'))..createSync();
    File(p.join(capas.path, 'capa_9.jpg')).writeAsBytesSync([9]);

    final dbPath = p.join(origem.path, DbHelper.nomeBancoRelease);
    final db = await openDatabase(
      dbPath,
      version: DbHelper.versaoDoBanco + 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE mangas (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            nome_pt TEXT NOT NULL,
            nome_en TEXT,
            capitulo INTEGER NOT NULL DEFAULT 1,
            link_url TEXT,
            capa_path TEXT,
            status_leitura TEXT NOT NULL,
            ordem_leitura INTEGER NOT NULL,
            tipo TEXT,
            coluna_do_futuro TEXT
          )''');
        await db.execute(
          'CREATE TABLE configuracoes (chave TEXT PRIMARY KEY, valor TEXT)',
        );
      },
    );
    await db.insert('mangas', {
      'nome_pt': 'Com tipo',
      'status_leitura': 'Lendo',
      'ordem_leitura': 1,
      'tipo': 'manhwa',
      'coluna_do_futuro': 'qualquer coisa',
    });
    await db.insert('mangas', {
      'nome_pt': 'Sem tipo',
      'status_leitura': 'Completo',
      'ordem_leitura': 2,
    });
    await db.close();

    final tarGz = p.join(raiz.path, 'backup_novo.tar.gz');
    await TarStreamHelper.compressToTarGz(
      dbPath: dbPath,
      capasDirPath: capas.path,
      tarGzPath: tarGz,
    );
    return tarGz;
  }

  test(
    'mesclar: copia o tipo e ignora coluna de uma versão mais nova',
    () async {
      final backup = await backupComTipo();

      final mensagem = await BackupService().restoreBackup(backup, merge: true);
      expect(mensagem, contains('2 novos'));

      final linhas = await DbHelper().getMangas();
      expect(
        {for (final l in linhas) l['nome_pt']: l['tipo']},
        {'Com tipo': 'manhwa', 'Sem tipo': null},
      );
    },
  );

  test('substituir: banco de antes do tipo ganha a coluna ao abrir', () async {
    final backup = await backupDoWindows();
    await BackupService().restoreBackup(backup, merge: false);

    final linhas = await DbHelper().getMangas();
    expect(linhas, hasLength(3));
    expect(linhas.every((l) => l.containsKey('tipo')), isTrue);
    expect(linhas.map((l) => l['tipo']), everyElement(isNull));
  });

  group('exportar', () {
    Future<File> capaNoApp() async {
      await DbHelper().database; // cria o banco do app
      final capas = await DbHelper().getCapasDirectory();
      capas.createSync(recursive: true);
      return File(p.join(capas.path, 'capa_1.jpg'))
        ..writeAsBytesSync([7, 8, 9]);
    }

    test('grava direto no destino, sem cópia na pasta temporária', () async {
      await capaNoApp();
      final destino = p.join(raiz.path, 'saida', 'onde_parei_backup.tar.gz');
      Directory(p.dirname(destino)).createSync();

      expect(await BackupService().exportBackup(destino), destino);

      final conferir = p.join(raiz.path, 'conferir');
      await TarStreamHelper.extractTarGz(
        tarGzPath: destino,
        destPath: conferir,
      );
      final nomeBanco = p.basename(await DbHelper().getDatabasePathString());
      expect(File(p.join(conferir, nomeBanco)).existsSync(), isTrue);
      expect(File(p.join(conferir, 'capas', 'capa_1.jpg')).readAsBytesSync(), [
        7,
        8,
        9,
      ]);

      // Antes o backup era gerado na pasta temporária e copiado
      final temp = Directory(p.join(raiz.path, 'temp'));
      final sobras = temp.existsSync() ? temp.listSync() : <FileSystemEntity>[];
      expect(sobras, isEmpty);
      // O banco volta a funcionar
      await DbHelper().database;
    });

    test(
      'erro no meio não deixa o arquivo pela metade',
      () async {
        final capa = await capaNoApp();
        // Trava a capa: a leitura dela falha no meio do backup
        final trava = capa.openSync(mode: FileMode.append)
          ..lockSync(FileLock.exclusive);
        final destino = p.join(raiz.path, 'onde_parei_backup.tar.gz');
        try {
          await expectLater(
            BackupService().exportBackup(destino),
            throwsA(isA<Exception>()),
          );
        } finally {
          trava
            ..unlockSync()
            ..closeSync();
        }

        expect(File(destino).existsSync(), isFalse);
        await DbHelper().database; // destravado e reaberto
      },
      // A trava de arquivo só impede a leitura no Windows (no Linux ela é
      // apenas um aviso entre programas)
      skip: !Platform.isWindows,
    );
  });

  group('manifesto', () {
    /// Nome e conteúdo de cada entrada do backup, na ordem.
    Future<List<(String, List<int>)>> entradasDe(String backup) async {
      final reader = TarReader(File(backup).openRead().transform(gzip.decoder));
      final entradas = <(String, List<int>)>[];
      while (await reader.moveNext()) {
        final e = reader.current;
        final bytes = await e.contents.fold<List<int>>(
          [],
          (a, b) => a..addAll(b),
        );
        entradas.add((e.name, bytes));
      }
      return entradas;
    }

    /// Regrava o [backup] sem as entradas [omitir] e com as [extras] no fim:
    /// um tar e um gzip válidos, como um corte exato entre dois arquivos.
    Future<String> regravar(
      String backup, {
      Set<String> omitir = const {},
      Map<String, List<int>> extras = const {},
    }) async {
      final entradas = <TarEntry>[
        for (final (nome, bytes) in await entradasDe(backup))
          if (!omitir.contains(nome))
            TarEntry.data(TarHeader(name: nome, mode: 420), bytes),
        for (final MapEntry(:key, :value) in extras.entries)
          TarEntry.data(TarHeader(name: key, mode: 420), value),
      ];
      final destino = p.join(raiz.path, 'regravado.tar.gz');
      await Stream.fromIterable(entradas)
          .transform(tarWriter)
          .transform(gzip.encoder)
          .pipe(File(destino).openWrite());
      return destino;
    }

    /// Dados que já estão no app antes de restaurar.
    Future<File> dadosAtuais() async {
      final db = await DbHelper().database;
      await db.insert('mangas', {
        'nome_pt': 'Meu atual',
        'status_leitura': 'Lendo',
        'ordem_leitura': 0,
      });
      final capas = await DbHelper().getCapasDirectory();
      capas.createSync(recursive: true);
      return File(p.join(capas.path, 'capa_atual.jpg'))
        ..writeAsBytesSync([9, 9, 9]);
    }

    test('vem primeiro e lista cada arquivo com o tamanho', () async {
      final entradas = await entradasDe(await backupDoWindows());

      expect(entradas.first.$1, TarStreamHelper.nomeManifesto);
      final manifesto = jsonDecode(utf8.decode(entradas.first.$2)) as Map;
      expect(manifesto['formato'], 1);
      expect(manifesto['arquivos'], {
        for (final (nome, bytes) in entradas.skip(1)) nome: bytes.length,
      });
      expect(
        (manifesto['arquivos'] as Map).keys,
        containsAll([
          DbHelper.nomeBancoRelease,
          'capas/capa_1.jpg',
          'capas/Capa_2.PNG',
        ]),
      );
    });

    test(
      'backup cortado entre dois arquivos para antes de mexer nos dados',
      () async {
        final capaAtual = await dadosAtuais();
        final cortado = await regravar(
          await backupDoWindows(),
          omitir: {'capas/Capa_2.PNG'},
        );

        await expectLater(
          BackupService().restoreBackup(cortado, merge: false),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'mensagem',
              allOf(
                contains('incompleto'),
                contains('1 de 3'),
                contains('capas/Capa_2.PNG'),
                contains('Nada foi alterado'),
              ),
            ),
          ),
        );

        expect(await capasNoBanco(), {'Meu atual': null});
        expect(capaAtual.readAsBytesSync(), [9, 9, 9]);
      },
    );

    test('backup sem manifesto (antes da v2.2.1) ainda restaura, e o '
        'manifest.json antigo não vira capa', () async {
      final antigo = await regravar(
        await backupDoWindows(),
        omitir: {TarStreamHelper.nomeManifesto},
        extras: {
          'manifest.json': utf8.encode('{"totalFiles":3,"totalBytes":1}'),
        },
      );

      final mensagem = await BackupService().restoreBackup(
        antigo,
        merge: false,
      );

      expect(mensagem, contains('sucesso'));
      final pastaCapas = (await DbHelper().getCapasDirectory()).path;
      expect(File(p.join(pastaCapas, 'capa_1.jpg')).existsSync(), isTrue);
      expect(File(p.join(pastaCapas, 'manifest.json')).existsSync(), isFalse);
    });

    test('confere arquivo faltando e com tamanho diferente', () {
      expect(
        TarStreamHelper.conferirManifesto(
          {'a': 1, 'b': 2, 'c': 3},
          {'a': 1, 'b': 5, 'extra': 7},
        ),
        ['b', 'c'],
      );
      expect(TarStreamHelper.conferirManifesto({'a': 1}, {'a': 1}), isEmpty);
    });

    test('mensagem mostra até três arquivos', () {
      final erro = BackupIncompleto(['a', 'b', 'c', 'd', 'e'], total: 10);
      expect(erro.mensagem, contains('5 de 10'));
      expect(erro.mensagem, contains('(a, b, c…)'));
    });
  });

  group('lerArquivo', () {
    // No Windows um arquivo aberto não pode ser apagado: apagar no fim prova
    // que a leitura fechou o arquivo
    File arquivoDe(int tamanho) =>
        File(p.join(raiz.path, 'dados.bin'))
          ..writeAsBytesSync(List.generate(tamanho, (i) => i % 251));

    test('lê o arquivo inteiro em pedaços e o fecha', () async {
      final arquivo = arquivoDe(150 * 1024);
      final pedacos = await TarStreamHelper.lerArquivo(arquivo).toList();
      expect(pedacos.length, 3);
      expect(pedacos.expand((e) => e).toList(), arquivo.readAsBytesSync());
      arquivo.deleteSync();
    });

    test('arquivo menor que o tamanho do cabeçalho dá erro', () async {
      final arquivo = arquivoDe(1000);
      await expectLater(
        TarStreamHelper.lerArquivo(arquivo, tamanho: 1010).toList(),
        throwsA(isA<FileSystemException>()),
      );
      arquivo.deleteSync();
    });

    test('desistir no meio fecha o arquivo', () async {
      final arquivo = arquivoDe(200 * 1024);
      await TarStreamHelper.lerArquivo(arquivo).first;
      arquivo.deleteSync();
    });
  });

  group('regras', () {
    test('nome do arquivo com barra normal ou invertida', () {
      expect(DbHelper.nomeDoArquivo(r'C:\pasta\capa.jpg'), 'capa.jpg');
      expect(
        DbHelper.nomeDoArquivo('/data/user/0/capas/capa.webp'),
        'capa.webp',
      );
      expect(DbHelper.nomeDoArquivo(r'C:\pasta/capa.png'), 'capa.png');
    });

    test('capa que não veio no backup mantém o caminho', () {
      expect(
        DbHelper.caminhoCapaRestaurada('/outro/x.jpg', '/aqui', {}),
        '/outro/x.jpg',
      );
      expect(DbHelper.caminhoCapaRestaurada(null, '/aqui', {}), isNull);
    });

    test('prefere o banco do modo atual e aceita o do outro', () {
      final release = File('/b/${DbHelper.nomeBancoRelease}');
      final debug = File('/b/${DbHelper.nomeBancoDebug}');
      expect(BackupService.bancoDoBackup([release, debug], debug: true), debug);
      expect(
        BackupService.bancoDoBackup([release, debug], debug: false),
        release,
      );
      expect(BackupService.bancoDoBackup([release], debug: true), release);
      expect(
        BackupService.bancoDoBackup([File('/b/x.jpg')], debug: true),
        isNull,
      );
    });

    test('aceita o banco do Manga Manager, mas prefere o de hoje', () {
      final antigo = File('/b/${DbHelper.nomeBancoReleaseAntigo}');
      final antigoDebug = File('/b/${DbHelper.nomeBancoDebugAntigo}');
      final atual = File('/b/${DbHelper.nomeBancoRelease}');
      expect(BackupService.bancoDoBackup([antigo], debug: false), antigo);
      expect(BackupService.bancoDoBackup([antigo], debug: true), antigo);
      expect(
        BackupService.bancoDoBackup([antigo, antigoDebug], debug: true),
        antigoDebug,
      );
      expect(BackupService.bancoDoBackup([antigo, atual], debug: true), atual);
      // Maiúsculas no nome (a extração no Windows passa para minúsculas)
      expect(
        BackupService.bancoDoBackup([
          File('/b/Manga_Manager.DB'),
        ], debug: false),
        isNotNull,
      );
    });
  });
}
