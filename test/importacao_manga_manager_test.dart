// Falha rápido se alguma chamada ficar sem resposta
@Timeout(Duration(seconds: 60))
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onde_parei/database/db_helper.dart';
import 'package:onde_parei/services/backup_service.dart';
import 'package:onde_parei/services/importacao_manga_manager.dart';
import 'package:onde_parei/services/update_service.dart';
import 'package:onde_parei/widgets/biblioteca_vazia.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'apoio/banco_de_teste.dart';

void main() {
  group('pastas do Manga Manager', () {
    test('ficam ao lado da pasta de dados deste app', () {
      expect(
        ImportacaoMangaManager.pastasDoMangaManager(
          r'C:\Users\u\AppData\Roaming\io.github.danielscarneiro\OndeParei',
          windows: true,
        ),
        [
          r'C:\Users\u\AppData\Roaming\com.example\manga_manager',
          r'C:\Users\u\AppData\Roaming\manga_manager',
        ],
      );
      expect(
        ImportacaoMangaManager.pastasDoMangaManager(
          '/home/u/.local/share/io.github.danielscarneiro.ondeparei',
          windows: false,
        ),
        [
          '/home/u/.local/share/com.example.manga_manager',
          '/home/u/.local/share/manga_manager',
        ],
      );
    });

    test('o banco: prefere o do modo atual e ignora arquivo vazio', () {
      final raiz = Directory.systemTemp.createTempSync('pastas_antigas');
      addTearDown(() => raiz.deleteSync(recursive: true));
      final pasta = raiz.path;
      final release = File(p.join(pasta, DbHelper.nomeBancoReleaseAntigo));
      final debug = File(p.join(pasta, DbHelper.nomeBancoDebugAntigo));

      expect(
        ImportacaoMangaManager.bancoNasPastas([pasta], debug: false),
        isNull,
      );

      release.writeAsBytesSync([1]);
      expect(
        ImportacaoMangaManager.bancoNasPastas([pasta], debug: true)?.path,
        release.path,
      );

      debug.writeAsBytesSync([1]);
      expect(
        ImportacaoMangaManager.bancoNasPastas([pasta], debug: true)?.path,
        debug.path,
      );
      expect(
        ImportacaoMangaManager.bancoNasPastas([pasta], debug: false)?.path,
        release.path,
      );

      // Banco vazio (zero bytes) não tem biblioteca
      release.writeAsBytesSync([]);
      debug.writeAsBytesSync([]);
      expect(
        ImportacaoMangaManager.bancoNasPastas([pasta], debug: false),
        isNull,
      );
      expect(
        ImportacaoMangaManager.bancoNasPastas([
          p.join(pasta, 'nao_existe'),
        ], debug: false),
        isNull,
      );
    });
  });

  group('importar do Manga Manager instalado neste computador', () {
    late Directory raiz;
    late File bancoAntigo;
    late File capaAntiga;
    late String capaSumida;

    setUpAll(iniciarSqfliteDeTeste);
    tearDown(() => encerrarBancoDeTeste(raiz));

    setUp(() async {
      raiz = await prepararBancoDeTeste('importar_teste');

      // Como o Manga Manager deixava os dados: banco v2 (sem a coluna tipo)
      // na pasta dele e o caminho completo das capas no banco
      final pastaAntiga = Directory(
        p.join(raiz.path, 'appdata', 'com.example', 'manga_manager'),
      )..createSync(recursive: true);
      final capasAntigas = Directory(
        p.join(raiz.path, 'documentos', 'manga_manager_capas'),
      )..createSync(recursive: true);
      capaAntiga = File(p.join(capasAntigas.path, 'capa_1.jpg'))
        ..writeAsBytesSync([7, 8, 9]);
      capaSumida = p.join(capasAntigas.path, 'capa_sumida.jpg');

      bancoAntigo = File(
        p.join(pastaAntiga.path, DbHelper.nomeBancoReleaseAntigo),
      );
      final db = await openDatabase(bancoAntigo.path);
      await db.execute('''
        CREATE TABLE mangas (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nome_pt TEXT NOT NULL,
          nome_en TEXT,
          capitulo INTEGER NOT NULL DEFAULT 1,
          link_url TEXT,
          capa_path TEXT,
          status_leitura TEXT NOT NULL DEFAULT 'Lendo',
          ordem_leitura INTEGER NOT NULL DEFAULT 0
        )''');
      await db.execute(
        'CREATE TABLE configuracoes (chave TEXT PRIMARY KEY, valor TEXT NOT NULL)',
      );
      await db.insert('configuracoes', {
        'chave': UpdateService.kVersaoApp,
        'valor': '2.2.2',
      });
      await db.insert('configuracoes', {'chave': 'tema', 'valor': 'light'});
      await db.insert('mangas', {
        'nome_pt': 'Com capa',
        'capa_path': capaAntiga.path,
        'ordem_leitura': 1,
      });
      await db.insert('mangas', {
        'nome_pt': 'Capa sumida',
        'capa_path': capaSumida,
        'ordem_leitura': 2,
      });
      await db.insert('mangas', {'nome_pt': 'Sem capa', 'ordem_leitura': 3});
      await db.setVersion(2);
      await db.close();
    });

    /// Nada sobra na pasta temporária
    void conferirPastaTemporaria() {
      final restos = Directory(p.join(raiz.path, 'temp'))
          .listSync()
          .map((e) => p.basename(e.path))
          .where((nome) => nome.startsWith('importar_'));
      expect(restos, isEmpty);
    }

    test(
      'com a biblioteca vazia, traz leituras, capas e configurações',
      () async {
        await DbHelper().setConfig(UpdateService.kVersaoApp, '3.0.0');
        final bytesAntes = bancoAntigo.readAsBytesSync();

        final mensagem = await BackupService().importarDoMangaManager(
          bancoAntigo,
          merge: false,
        );
        expect(mensagem, 'Biblioteca do Manga Manager importada: 3 leituras.');

        final linhas = await DbHelper().getMangas();
        expect(linhas.map((l) => l['nome_pt']), [
          'Com capa',
          'Capa sumida',
          'Sem capa',
        ]);
        expect(linhas.map((l) => l['tipo']), everyElement(isNull));

        final pastaCapas = (await DbHelper().getCapasDirectory()).path;
        final comCapa = linhas.first['capa_path'] as String;
        expect(comCapa, p.join(pastaCapas, 'capa_1.jpg'));
        expect(File(comCapa).readAsBytesSync(), [7, 8, 9]);
        // A capa que não existia mais fica com o caminho de antes
        expect(linhas[1]['capa_path'], capaSumida);
        // O banco do Manga Manager não vira capa
        expect(
          File(
            p.join(pastaCapas, DbHelper.nomeBancoReleaseAntigo),
          ).existsSync(),
          isFalse,
        );

        // As configurações vêm junto, menos a versão do app daqui (senão a
        // próxima abertura diria "Onde Parei atualizado")
        expect(await DbHelper().getConfig('tema'), 'light');
        expect(await DbHelper().getConfig(UpdateService.kVersaoApp), '3.0.0');

        // O Manga Manager fica como estava
        expect(bancoAntigo.readAsBytesSync(), bytesAntes);
        expect(capaAntiga.existsSync(), isTrue);
        conferirPastaTemporaria();
      },
    );

    test('sem versão gravada aqui, a do Manga Manager não fica', () async {
      await BackupService().importarDoMangaManager(bancoAntigo, merge: false);
      expect(await DbHelper().getConfig(UpdateService.kVersaoApp), isNull);
    });

    test('com leituras, acrescenta só as que faltam', () async {
      await DbHelper().insertManga({
        'nome_pt': 'Com capa',
        'capitulo': 40,
        'status_leitura': 'Lendo',
      });

      final mensagem = await BackupService().importarDoMangaManager(
        bancoAntigo,
        merge: true,
      );
      expect(
        mensagem,
        'Importação concluída: 2 leituras novas do Manga Manager.',
      );

      final linhas = await DbHelper().getMangas();
      expect(linhas, hasLength(3));
      // A que já estava aqui não muda
      final daqui = linhas.firstWhere((l) => l['nome_pt'] == 'Com capa');
      expect(daqui['capitulo'], 40);
      expect(daqui['capa_path'], isNull);
      conferirPastaTemporaria();
    });

    test('banco que sumiu: avisa e não mexe na biblioteca', () async {
      await DbHelper().insertManga({
        'nome_pt': 'Daqui',
        'capitulo': 1,
        'status_leitura': 'Lendo',
      });
      bancoAntigo.deleteSync();

      await expectLater(
        BackupService().importarDoMangaManager(bancoAntigo, merge: false),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'mensagem',
            contains('não foi encontrado'),
          ),
        ),
      );
      final linhas = await DbHelper().getMangas();
      expect(linhas.map((l) => l['nome_pt']), ['Daqui']);
      conferirPastaTemporaria();
    });

    testWidgetsComBanco('pela lista vazia: confirma, importa e avisa', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BibliotecaVazia(bancoDoMangaManager: bancoAntigo),
          ),
        ),
      );
      expect(find.textContaining('Vindo do Manga Manager?'), findsNothing);

      await tester.tap(find.text('Importar do Manga Manager'));
      // A biblioteca daqui está vazia: a importação traz tudo
      await esperarPor(tester, find.textContaining('Traz as leituras'));
      await tester.tap(find.text('Importar'));
      await tester.pump();
      expect(find.text('Importando a biblioteca...'), findsOneWidget);

      await esperarPor(
        tester,
        find.text('Biblioteca do Manga Manager importada: 3 leituras.'),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Importando a biblioteca...'), findsNothing);
      final linhas = await tester.runAsync(() => DbHelper().getMangas());
      expect(linhas, hasLength(3));
    });

    testWidgetsComBanco('com leituras aqui, o diálogo diz que só acrescenta', (
      tester,
    ) async {
      await tester.runAsync(
        () => DbHelper().insertManga({
          'nome_pt': 'Daqui',
          'capitulo': 1,
          'status_leitura': 'Lendo',
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BibliotecaVazia(bancoDoMangaManager: bancoAntigo),
          ),
        ),
      );

      await tester.tap(find.text('Importar do Manga Manager'));
      await esperarPor(tester, find.textContaining('Acrescenta as leituras'));
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      final linhas = await tester.runAsync(() => DbHelper().getMangas());
      expect(linhas!.map((l) => l['nome_pt']), ['Daqui']);
    });
  });

  testWidgets('lista vazia sem o Manga Manager aqui: explica o backup', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: BibliotecaVazia())),
    );
    expect(find.textContaining('Nova Leitura'), findsOneWidget);
    expect(find.textContaining('Vindo do Manga Manager?'), findsOneWidget);
    expect(find.textContaining('Backup / Restaurar'), findsOneWidget);
    expect(find.text('Importar do Manga Manager'), findsNothing);
  });
}

/// `testWidgets` com o banco de teste. O apoio do banco finge ser o Windows
/// (as pastas do DbHelper dependem da plataforma), e o `testWidgets` exige
/// que a troca seja desfeita antes do fim do corpo do teste.
void testWidgetsComBanco(String descricao, WidgetTesterCallback corpo) {
  testWidgets(descricao, (tester) async {
    try {
      await corpo(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

/// Deixa o banco e os arquivos (I/O de verdade) andarem até [alvo] aparecer.
Future<void> esperarPor(WidgetTester tester, Finder alvo) async {
  for (var i = 0; i < 200 && alvo.evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
  }
  expect(alvo, findsOneWidget);
}
