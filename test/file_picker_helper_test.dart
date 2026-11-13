// Falha rápido se alguma chamada ficar sem resposta
@Timeout(Duration(seconds: 60))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onde_parei/utils/file_picker_helper.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _PastaTemporaria extends PathProviderPlatform {
  _PastaTemporaria(this.pasta);
  final String pasta;

  @override
  Future<String?> getTemporaryPath() async => pasta;
}

/// Seletor que só conta as limpezas do cache (no Android, a pasta
/// cache/file_picker com as cópias dos arquivos escolhidos).
class _SeletorFalso extends FilePickerPlatform {
  int limpezas = 0;
  bool falharNaLimpeza = false;

  @override
  Future<void> clearTemporaryFiles() async {
    limpezas++;
    if (falharNaLimpeza) throw const FileSystemException('cache travado');
  }
}

/// Arquivo escolhido: do disco (`file://`) ou só uma URI (`content://`).
final class _Escolhido extends PlatformFile {
  _Escolhido(this.uri, this._bytes);

  @override
  final Uri uri;
  final List<int> _bytes;

  @override
  String get name => uri.pathSegments.last;
  @override
  get xFile => throw UnimplementedError();
  @override
  int? lengthSync() => _bytes.length;
  @override
  Future<int?> length() async => _bytes.length;
  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList(_bytes);
  @override
  Stream<Uint8List> readAsByteStream() =>
      Stream.value(Uint8List.fromList(_bytes));
}

void main() {
  late Directory raiz;
  late String temp;
  late _SeletorFalso seletor;

  setUp(() {
    raiz = Directory.systemTemp.createTempSync('seletor_teste');
    temp = (Directory(p.join(raiz.path, 'temp'))..createSync()).path;
    PathProviderPlatform.instance = _PastaTemporaria(temp);
    seletor = _SeletorFalso();
    FilePickerPlatform.instance = seletor;
  });

  tearDown(() => raiz.deleteSync(recursive: true));

  _Escolhido soUri() => _Escolhido(
    Uri.parse(
      'content://com.android.providers/documento/onde_parei_backup.tar.gz',
    ),
    [1, 2, 3],
  );

  test('arquivo do disco: usa o original e nunca o apaga', () async {
    final original = File(p.join(raiz.path, 'onde_parei_backup.tar.gz'))
      ..writeAsBytesSync([4, 5, 6]);

    final usado = await usarArquivoEscolhido(
      _Escolhido(Uri.file(original.path), [4, 5, 6]),
      (caminho) async => caminho,
    );

    expect(usado, original.path);
    expect(original.readAsBytesSync(), [4, 5, 6]);
    expect(seletor.limpezas, 1);
  });

  test('só URI: usa uma cópia temporária e a apaga no fim', () async {
    late String copia;
    final resultado = await usarArquivoEscolhido(soUri(), (caminho) async {
      copia = caminho;
      expect(p.isWithin(temp, caminho), isTrue, reason: caminho);
      expect(File(caminho).readAsBytesSync(), [1, 2, 3]);
      return 'restaurado';
    });

    expect(resultado, 'restaurado');
    expect(File(copia).existsSync(), isFalse);
    expect(seletor.limpezas, 1);
  });

  test('erro no uso: apaga a cópia e repassa o erro', () async {
    late String copia;
    await expectLater(
      usarArquivoEscolhido(soUri(), (caminho) async {
        copia = caminho;
        throw StateError('backup corrompido');
      }),
      throwsStateError,
    );

    expect(File(copia).existsSync(), isFalse);
    expect(seletor.limpezas, 1);
  });

  test('falha ao limpar o cache não esconde o resultado', () async {
    seletor.falharNaLimpeza = true;

    final resultado = await usarArquivoEscolhido(
      soUri(),
      (caminho) async => 'restaurado',
    );

    expect(resultado, 'restaurado');
    expect(seletor.limpezas, 1);
  });
}
