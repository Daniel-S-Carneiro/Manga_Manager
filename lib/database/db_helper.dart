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
    String dbName = kDebugMode ? 'manga_manager_debug.db' : 'manga_manager.db';
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

    final currentDb = await database;
    int inseridos = 0;
    final realCapasDir = await getCapasDirectory();

    Map<String, io.File> mapaCapas = {};
    for (var entidade in pastaTemporaria.listSync(recursive: true)) {
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
            await arquivoCapaReal.copy(
              p.join(realCapasDir.path, nomeArquivoCapa),
            );
          }
        }
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
