import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Caminho local do arquivo escolhido no seletor.
///
/// No desktop o seletor devolve um arquivo do disco. No Android ele pode
/// devolver só uma URI (content://), sem caminho: nesse caso o conteúdo é
/// copiado para a pasta temporária e o caminho da cópia é devolvido.
Future<String> caminhoLocalDoArquivo(PlatformFile arquivo) async {
  final path = arquivo.path;
  if (path != null) return path;
  return (await _copiarParaTemporario(arquivo)).path;
}

/// Roda [usar] com um caminho local do arquivo escolhido e, no fim (com ou
/// sem erro), apaga as cópias temporárias dele: a que este helper faz quando
/// o seletor devolve só uma URI, e a que o próprio file_picker guarda no
/// cache do Android (`FilePicker.clearTemporaryFiles`, que nos outros
/// sistemas não faz nada). O arquivo original do usuário nunca é apagado.
///
/// Para arquivos grandes, como o backup: cada restauração deixava uma cópia
/// inteira dele no celular.
Future<T> usarArquivoEscolhido<T>(
  PlatformFile arquivo,
  Future<T> Function(String caminho) usar,
) async {
  final copia = arquivo.path == null
      ? await _copiarParaTemporario(arquivo)
      : null;
  try {
    return await usar(copia?.path ?? arquivo.path!);
  } finally {
    if (copia != null) {
      try {
        await copia.delete();
      } catch (_) {}
    }
    try {
      await FilePicker.clearTemporaryFiles();
    } catch (_) {}
  }
}

Future<File> _copiarParaTemporario(PlatformFile arquivo) async {
  final tempDir = await getTemporaryDirectory();
  final destino = File(
    p.join(
      tempDir.path,
      'escolhido_${DateTime.now().millisecondsSinceEpoch}_${p.basename(arquivo.name)}',
    ),
  );

  final sink = destino.openWrite();
  try {
    await sink.addStream(arquivo.readAsByteStream());
  } finally {
    await sink.close();
  }
  return destino;
}
