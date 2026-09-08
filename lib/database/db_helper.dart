import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'dart:io' as io;

class DbHelper {
  static final DbHelper _instance = DbHelper._internal();
  factory DbHelper() => _instance;
  DbHelper._internal();

  static Database? _database;

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

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path;
    String dbName = kDebugMode ? 'manga_manager_debug.db' : 'manga_manager.db';

    if (kIsWeb) {
      databaseFactory = databaseFactoryFfiWeb;
      path = dbName;
    } else {
      if (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;

        final directory = await getApplicationSupportDirectory();

        if (!await directory.exists()) {
          await directory.create(recursive: true);
        }

        path = p.join(directory.path, dbName);
      } else {
        final dbPath = await getDatabasesPath();
        path = p.join(dbPath, dbName);
      }
    }

    return await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
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
