// Falha rápido se alguma chamada ficar sem resposta
@Timeout(Duration(seconds: 60))
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_manager/database/db_helper.dart';
import 'package:manga_manager/services/backup_service.dart';
import 'package:manga_manager/utils/tar_stream_helper.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Pastas do sistema trocadas por pastas temporárias: a restauração apaga o
/// banco e as capas, e não pode tocar nos dados reais do computador.
class _PastasDeTeste extends PathProviderPlatform {
  _PastasDeTeste(this.raiz);
  final String raiz;

  String _pasta(String nome) =>
      (Directory(p.join(raiz, nome))..createSync(recursive: true)).path;

  @override
  Future<String?> getTemporaryPath() async => _pasta('temp');
  @override
  Future<String?> getApplicationSupportPath() async => _pasta('suporte');
  @override
  Future<String?> getApplicationDocumentsPath() async => _pasta('documentos');
}

void main() {
  late Directory raiz;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    raiz = Directory.systemTemp.createTempSync('backup_teste');
    PathProviderPlatform.instance = _PastasDeTeste(raiz.path);
    // Nos testes o Flutter finge ser Android, e o DbHelper iria para a pasta
    // de bancos do sqflite: como computador, ele usa as pastas acima
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    // Trava de segurança: nada fora da pasta temporária
    final banco = await DbHelper().getDatabasePathString();
    final capas = await DbHelper().getCapasDirectory();
    expect(p.isWithin(raiz.path, banco), isTrue, reason: banco);
    expect(p.isWithin(raiz.path, capas.path), isTrue, reason: capas.path);
  });

  tearDown(() async {
    await DbHelper().closeDatabase();
    DbHelper().unlockDatabase();
    debugDefaultTargetPlatformOverride = null;
    raiz.deleteSync(recursive: true);
  });

  /// Backup como o que o app do Windows gera: `manga_manager.db` (app
  /// instalado) com o caminho das capas no Windows, e a pasta `capas/`.
  Future<String> backupDoWindows() async {
    final origem = Directory(p.join(raiz.path, 'origem'))..createSync();
    final capas = Directory(p.join(origem.path, 'capas'))..createSync();
    File(p.join(capas.path, 'capa_1.jpg')).writeAsBytesSync([1, 2, 3]);
    File(p.join(capas.path, 'Capa_2.PNG')).writeAsBytesSync([4, 5, 6]);

    final dbPath = p.join(origem.path, DbHelper.nomeBancoRelease);
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

    final tarGz = p.join(raiz.path, 'manga_backup.tar.gz');
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
      final destino = p.join(raiz.path, 'saida', 'manga_backup.tar.gz');
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
        final destino = p.join(raiz.path, 'manga_backup.tar.gz');
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
  });
}
