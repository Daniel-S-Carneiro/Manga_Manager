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
  return destino.path;
}
