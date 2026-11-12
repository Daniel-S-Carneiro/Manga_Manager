import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manga_manager/database/db_helper.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Pastas do sistema trocadas por pastas temporárias: a restauração apaga o
/// banco e as capas, e os testes não podem tocar nos dados reais.
class PastasDeTeste extends PathProviderPlatform {
  PastasDeTeste(this.raiz);
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

/// Liga o sqflite por FFI (no `setUpAll`).
void iniciarSqfliteDeTeste() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

/// Põe o [DbHelper] numa pasta temporária nova (no `setUp`) e devolve a
/// pasta, que [encerrarBancoDeTeste] apaga.
Future<Directory> prepararBancoDeTeste(String prefixo) async {
  final raiz = Directory.systemTemp.createTempSync(prefixo);
  PathProviderPlatform.instance = PastasDeTeste(raiz.path);
  // Nos testes o Flutter finge ser Android, e o DbHelper iria para a pasta
  // de bancos do sqflite: como computador, ele usa as pastas acima
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  // Trava de segurança: nada fora da pasta temporária
  final banco = await DbHelper().getDatabasePathString();
  final capas = await DbHelper().getCapasDirectory();
  expect(p.isWithin(raiz.path, banco), isTrue, reason: banco);
  expect(p.isWithin(raiz.path, capas.path), isTrue, reason: capas.path);
  return raiz;
}

/// Fecha o banco, solta a trava e apaga a pasta (no `tearDown`).
Future<void> encerrarBancoDeTeste(Directory raiz) async {
  await DbHelper().closeDatabase();
  DbHelper().unlockDatabase();
  debugDefaultTargetPlatformOverride = null;
  raiz.deleteSync(recursive: true);
}
