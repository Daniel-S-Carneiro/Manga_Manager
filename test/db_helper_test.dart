// Falha rápido se alguma chamada ficar sem resposta
@Timeout(Duration(seconds: 60))
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onde_parei/database/db_helper.dart';
import 'package:onde_parei/utils/classificacao.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'apoio/banco_de_teste.dart';

void main() {
  late Directory raiz;

  setUpAll(iniciarSqfliteDeTeste);
  setUp(() async => raiz = await prepararBancoDeTeste('banco_teste'));
  tearDown(() => encerrarBancoDeTeste(raiz));

  /// Schema de `mangas` até a v2 do banco (sem `tipo`).
  const mangasV2 = '''
    CREATE TABLE mangas (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nome_pt TEXT NOT NULL,
      nome_en TEXT,
      capitulo INTEGER NOT NULL DEFAULT 1,
      link_url TEXT,
      capa_path TEXT,
      status_leitura TEXT NOT NULL,
      ordem_leitura INTEGER NOT NULL
    )''';
  const configuracoes =
      'CREATE TABLE configuracoes (chave TEXT PRIMARY KEY, valor TEXT NOT NULL)';

  Map<String, Object?> linha(String nome, {int ordem = 1, String? tipo}) => {
    'nome_pt': nome,
    'status_leitura': 'Lendo',
    'ordem_leitura': ordem,
    'tipo': ?tipo,
  };

  /// Grava no lugar do banco do app um banco feito por [criar], com a
  /// [versao] dada (0 = sem versão, como um banco aberto sem `version`).
  Future<void> bancoExistente(
    int versao,
    Future<void> Function(Database db) criar,
  ) async {
    final caminho = await DbHelper().getDatabasePathString();
    final db = await openDatabase(caminho);
    await criar(db);
    await db.setVersion(versao);
    await db.close();
  }

  Future<List<String>> colunasDosMangas() async {
    final db = await DbHelper().database;
    final info = await db.rawQuery('PRAGMA table_info(mangas)');
    return [for (final c in info) c['name'] as String];
  }

  group('migração', () {
    test('banco v2 ganha a coluna tipo e mantém os dados', () async {
      await bancoExistente(2, (db) async {
        await db.execute(mangasV2);
        await db.execute(configuracoes);
        await db.insert('mangas', linha('Antigo'));
        await db.insert('configuracoes', {'chave': 'tema', 'valor': 'light'});
      });

      expect(await colunasDosMangas(), contains('tipo'));
      final db = await DbHelper().database;
      expect(await db.getVersion(), DbHelper.versaoDoBanco);

      final mangas = await DbHelper().getMangas();
      expect(mangas.single['nome_pt'], 'Antigo');
      expect(mangas.single['tipo'], isNull);
      expect(await DbHelper().getTema(), 'light');
    });

    test(
      'banco que um app antigo rebaixou para a v2, já com a coluna, abre sem '
      'erro e mantém o tipo',
      () async {
        // O app antigo só troca o número da versão e não mexe nas colunas
        await bancoExistente(2, (db) async {
          await db.execute(mangasV2);
          await db.execute('ALTER TABLE mangas ADD COLUMN tipo TEXT');
          await db.execute(configuracoes);
          await db.insert('mangas', linha('Novo', tipo: 'novel'));
        });

        expect(await colunasDosMangas(), contains('tipo'));
        final mangas = await DbHelper().getMangas();
        expect(mangas.single['tipo'], 'novel');
      },
    );

    test(
      'banco sem versão que já tem a tabela sem tipo (backup antigo) ganha a '
      'coluna',
      () async {
        // Com versão 0 o sqflite chama o onCreate, não o onUpgrade
        await bancoExistente(0, (db) async {
          await db.execute(mangasV2);
          await db.insert('mangas', linha('Do backup'));
        });

        expect(await colunasDosMangas(), contains('tipo'));
        expect((await DbHelper().getMangas()).single['nome_pt'], 'Do backup');
      },
    );

    test('banco novo já nasce com a coluna tipo', () async {
      expect(await colunasDosMangas(), ['id', ...DbHelper.colunasDosMangas]);
      expect(await DbHelper().getTema(), 'dark');
    });
  });

  group('getMangas com filtros', () {
    setUp(() async {
      final itens = [
        ('Alpha', 'Solo', 'manhwa', 'Lendo'),
        ('Beta', 'Alpha EN', 'manga', 'Completo'),
        ('Gama', null, null, 'Lendo'),
        // Chave de uma versão mais nova: aparece como sem tipo
        ('Delta', null, 'chave_do_futuro', 'Dropado'),
        ('Épsilon', null, 'manhwa', 'Completo'),
      ];
      for (final (nome, nomeEn, tipo, status) in itens) {
        await DbHelper().insertManga({
          'nome_pt': nome,
          'nome_en': nomeEn,
          'tipo': tipo,
          'status_leitura': status,
        });
      }
    });

    Future<List<String>> nomes(
      FiltroLista filtro, {
      int limite = 50,
      int offset = 0,
    }) async => [
      for (final m in await DbHelper().getMangas(
        filtro: filtro,
        limit: limite,
        offset: offset,
      ))
        m['nome_pt'] as String,
    ];

    test('sem filtro traz todos na ordem de leitura', () async {
      expect(await nomes(const FiltroLista()), [
        'Alpha',
        'Beta',
        'Gama',
        'Delta',
        'Épsilon',
      ]);
    });

    test('por tipo, sem tipo e por status', () async {
      expect(
        await nomes(const FiltroLista(tipo: FiltroTipo.de(TipoLeitura.manhwa))),
        ['Alpha', 'Épsilon'],
      );
      expect(await nomes(const FiltroLista(tipo: FiltroTipo.semTipo)), [
        'Gama',
        'Delta',
      ]);
      expect(await nomes(const FiltroLista(status: StatusLeitura.completo)), [
        'Beta',
        'Épsilon',
      ]);
      expect(
        await nomes(
          const FiltroLista(
            tipo: FiltroTipo.de(TipoLeitura.manhwa),
            status: StatusLeitura.completo,
          ),
        ),
        ['Épsilon'],
      );
      expect(
        await nomes(const FiltroLista(tipo: FiltroTipo.de(TipoLeitura.novel))),
        isEmpty,
      );
    });

    test('o OR da busca não escapa do filtro', () async {
      // "alpha" está no nome do Alpha (manhwa) e no nome em inglês do Beta
      expect(
        await nomes(
          const FiltroLista(
            busca: ' alpha ',
            tipo: FiltroTipo.de(TipoLeitura.manga),
          ),
        ),
        ['Beta'],
      );
      expect(await nomes(const FiltroLista(busca: 'alpha')), ['Alpha', 'Beta']);
    });

    test('getMangaNoFiltro: o item editado ainda combina?', () async {
      const manhwa = FiltroLista(tipo: FiltroTipo.de(TipoLeitura.manhwa));
      final alpha = (await DbHelper().getMangas(filtro: manhwa)).first;
      final id = alpha['id'] as int;
      expect(
        (await DbHelper().getMangaNoFiltro(id, manhwa))?['nome_pt'],
        'Alpha',
      );

      // Virou mangá: sai do filtro de manhwa, continua sem filtro
      await DbHelper().updateManga(id, {'tipo': 'manga'});
      expect(await DbHelper().getMangaNoFiltro(id, manhwa), isNull);
      expect(
        (await DbHelper().getMangaNoFiltro(id, const FiltroLista()))?['tipo'],
        'manga',
      );
      // Busca com OR: o nome em inglês do Beta tem "alpha", o Alpha não
      // pode entrar pelo OR
      expect(
        await DbHelper().getMangaNoFiltro(
          id,
          const FiltroLista(busca: 'solo', status: StatusLeitura.completo),
        ),
        isNull,
      );
      expect(
        await DbHelper().getMangaNoFiltro(9999, const FiltroLista()),
        isNull,
      );
    });

    test('a paginação respeita o filtro', () async {
      const filtro = FiltroLista(tipo: FiltroTipo.de(TipoLeitura.manhwa));
      expect(await nomes(filtro, limite: 1), ['Alpha']);
      expect(await nomes(filtro, limite: 1, offset: 1), ['Épsilon']);
      expect(await nomes(filtro, limite: 1, offset: 2), isEmpty);
    });
  });

  test('ordem_leitura repetida: os lotes não repetem nem pulam', () async {
    // A mescla do backup pode trazer a ordem_leitura de outro aparelho
    final db = await DbHelper().database;
    for (var i = 0; i < 6; i++) {
      await db.insert('mangas', linha('Item $i', ordem: i.isEven ? 1 : 2));
    }

    final vistos = <Object?>[];
    for (var offset = 0; offset < 6; offset += 2) {
      final lote = await DbHelper().getMangas(limit: 2, offset: offset);
      vistos.addAll(lote.map((m) => m['id']));
    }
    expect(vistos.toSet(), hasLength(6));
  });
}
