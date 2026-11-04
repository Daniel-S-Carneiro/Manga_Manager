import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io' as io;

class DbHelper {
  static final DbHelper _instance = DbHelper._internal();
  factory DbHelper() => _instance;
  DbHelper._internal();

  static Database? _database;
  bool _isLocked = false;

  void _checkLock() {
    if (_isLocked) {
      throw Exception(
        'Banco de dados em manutenção (Backup/Restore em andamento).',
      );
    }
  }

  void lockDatabase() => _isLocked = true;
  void unlockDatabase() => _isLocked = false;

  /// Nome do arquivo de banco de cada modo (o debug usa dados separados).
  static const String nomeBancoRelease = 'manga_manager.db';
  static const String nomeBancoDebug = 'manga_manager_debug.db';

  /// O banco aberto para o backup e a restauração, que rodam com o banco
  /// travado para o resto do app ([database] lança exceção nesse período).
  Future<Database> bancoEmManutencao() async {
    if (_database != null && _database!.isOpen) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Nome do arquivo no fim de um caminho, com barra normal ou invertida:
  /// o banco pode vir de outro sistema (um backup do Windows no celular).
  static String nomeDoArquivo(String caminho) =>
      caminho.split(RegExp(r'[\\/]')).last;

  /// Caminho da capa depois de restaurar um backup. O banco guarda o caminho
  /// completo do aparelho de origem (ex.: `C:\...\manga_manager_capas/capa_1.jpg`);
  /// se a capa veio no backup, passa a apontar para [pastaCapas] daqui.
  /// [capasDoBackup] vai do nome em minúsculas para o nome do arquivo.
  static String? caminhoCapaRestaurada(
    String? original,
    String pastaCapas,
    Map<String, String> capasDoBackup,
  ) {
    if (original == null || original.isEmpty) return original;
    final nome = capasDoBackup[nomeDoArquivo(original).toLowerCase()];
    return nome == null ? original : p.join(pastaCapas, nome);
  }

  /// Depois de substituir o banco pelo do backup: as capas que vieram nele
  /// passam a apontar para [pastaCapas]. Devolve quantas mudaram.
  Future<int> corrigirCaminhosDasCapas(
    String pastaCapas,
    Map<String, String> capasDoBackup,
  ) async {
    final db = await bancoEmManutencao();
    final mangas = await db.query('mangas', columns: ['id', 'capa_path']);
    var corrigidos = 0;
    await db.transaction((txn) async {
      for (final manga in mangas) {
        final atual = manga['capa_path'] as String?;
        final novo = caminhoCapaRestaurada(atual, pastaCapas, capasDoBackup);
        if (novo != atual) {
          await txn.update(
            'mangas',
            {'capa_path': novo},
            where: 'id = ?',
            whereArgs: [manga['id']],
          );
          corrigidos++;
        }
      }
    });
    return corrigidos;
  }

  Future<io.Directory> getCapasDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final folderName = kDebugMode
        ? 'manga_manager_capas_debug'
        : 'manga_manager_capas';
    final capasDir = io.Directory(p.join(appDir.path, folderName));
    if (!await capasDir.exists()) {
      await capasDir.create(recursive: true);
    }
    return capasDir;
  }

  Future<String> getDatabasePathString() async {
    String dbName = kDebugMode ? nomeBancoDebug : nomeBancoRelease;
    if (kIsWeb) return dbName;

    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      final directory = await getApplicationSupportDirectory();
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return p.join(directory.path, dbName);
    } else {
      final dbPath = await getDatabasesPath();
      return p.join(dbPath, dbName);
    }
  }

  Future<Database> get database async {
    _checkLock();
    if (_database != null && _database!.isOpen) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = await getDatabasePathString();
    return await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> closeDatabase() async {
    if (_database != null) {
      if (_database!.isOpen) await _database!.close();
      _database = null;
    }
  }

  Future<void> reopenDatabase() async {
    await closeDatabase();
    _database = await _initDatabase();
  }

  Future<int> mergeFromBackup(
    String tempDbPath,
    io.Directory pastaTemporaria,
  ) async {
    final tempDb = await openDatabase(tempDbPath);
    final List<Map<String, dynamic>> tempMangas = await tempDb.query('mangas');
    await tempDb.close();

    // Roda com o banco travado para o resto do app (restauração em andamento)
    final currentDb = await bancoEmManutencao();
    int inseridos = 0;
    final realCapasDir = await getCapasDirectory();

    Map<String, io.File> mapaCapas = {};
    for (var entidade in pastaTemporaria.listSync(recursive: true)) {
      if (entidade is io.File) {
        mapaCapas[p.basename(entidade.path).toLowerCase()] = entidade;
      }
    }
    final nomesCapas = {
      for (final e in mapaCapas.entries) e.key: p.basename(e.value.path),
    };

    for (var manga in tempMangas) {
      List<Map> existe = await currentDb.query(
        'mangas',
        where: 'nome_pt = ?',
        whereArgs: [manga['nome_pt']],
      );

      if (existe.isEmpty) {
        var novoManga = Map<String, dynamic>.from(manga)..remove('id');

        final capaPath = manga['capa_path'] as String?;
        final arquivoCapa = capaPath == null || capaPath.isEmpty
            ? null
            : mapaCapas[nomeDoArquivo(capaPath).toLowerCase()];
        if (arquivoCapa != null && arquivoCapa.existsSync()) {
          await arquivoCapa.copy(
            p.join(realCapasDir.path, p.basename(arquivoCapa.path)),
          );
          // O caminho no backup é o do aparelho de origem
          novoManga['capa_path'] = caminhoCapaRestaurada(
            capaPath,
            realCapasDir.path,
            nomesCapas,
          );
        }

        await currentDb.insert('mangas', novoManga);
        inseridos++;
      }
    }
    return inseridos;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS mangas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nome_pt TEXT NOT NULL,
        nome_en TEXT,
        capitulo INTEGER NOT NULL DEFAULT 1,
        link_url TEXT,
        capa_path TEXT,
        status_leitura TEXT NOT NULL,
        ordem_leitura INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS configuracoes (
        chave TEXT PRIMARY KEY,
        valor TEXT NOT NULL
      )
    ''');

    await db.execute('''
      INSERT OR IGNORE INTO configuracoes (chave, valor) VALUES ('tema', 'dark')
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS configuracoes (
          chave TEXT PRIMARY KEY,
          valor TEXT NOT NULL
        )
      ''');

      await db.execute('''
        INSERT OR IGNORE INTO configuracoes (chave, valor) VALUES ('tema', 'dark')
      ''');
    }
  }

  Future<String> getTema() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'configuracoes',
      where: 'chave = ?',
      whereArgs: ['tema'],
    );

    if (maps.isNotEmpty) {
      return maps.first['valor'] as String;
    }
    return 'dark';
  }

  Future<void> setTema(String tema) async {
    final db = await database;
    await db.insert('configuracoes', {
      'chave': 'tema',
      'valor': tema,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> setConfig(String chave, String valor) async {
    final db = await database;
    await db.insert('configuracoes', {
      'chave': chave,
      'valor': valor,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getConfig(String chave) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'configuracoes',
      where: 'chave = ?',
      whereArgs: [chave],
    );

    if (maps.isNotEmpty) {
      return maps.first['valor'] as String;
    }
    return null;
  }

  Future<int> insertManga(Map<String, dynamic> row) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.rawQuery(
      'SELECT MAX(ordem_leitura) as maxOrdem FROM mangas',
    );
    int nextOrdem = (maps.first['maxOrdem'] ?? 0) as int;
    row['ordem_leitura'] = nextOrdem + 1;

    return await db.insert('mangas', row);
  }

  Future<List<Map<String, dynamic>>> getMangas({
    int limit = 50,
    int offset = 0,
    String query = '',
  }) async {
    final db = await database;

    String? whereClause;
    List<dynamic>? whereArgs;

    if (query.trim().isNotEmpty) {
      final searchPattern = '%${query.trim()}%';
      whereClause = 'nome_pt LIKE ? OR nome_en LIKE ?';
      whereArgs = [searchPattern, searchPattern];
    }

    return await db.query(
      'mangas',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'ordem_leitura ASC',
      limit: limit,
      offset: offset,
    );
  }

  Future<void> reordenarMangas(List<Map<String, dynamic>> listaOrdenada) async {
    final db = await database;
    await db.transaction((txn) async {
      for (int i = 0; i < listaOrdenada.length; i++) {
        await txn.update(
          'mangas',
          {'ordem_leitura': i + 1},
          where: 'id = ?',
          whereArgs: [listaOrdenada[i]['id']],
        );
      }
    });
  }

  Future<int> deleteManga(int id) async {
    final db = await database;
    return await db.delete('mangas', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> updateManga(int id, Map<String, dynamic> dados) async {
    final db = await database;
    await db.update('mangas', dados, where: 'id = ?', whereArgs: [id]);
  }
}
