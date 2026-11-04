import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;

import '../database/db_helper.dart';
import 'file_picker_helper.dart';

/// Capas dos mangás: como são gravadas (formulários de novo e de edição) e
/// em que tamanho são decodificadas para aparecer no card.
class CapaHelper {
  /// Tamanho mínimo da capa gravada no Android e no Linux. O compressor só
  /// reduz, nunca aumenta, até um dos lados chegar aqui: dá para o card
  /// (320 de altura) ficar nítido em telas de até 3x de densidade. Antes era
  /// 300×450, e o celular (2,75x) esticava a capa umas duas vezes.
  static const int larguraGravada = 720;
  static const int alturaGravada = 1080;
  static const int qualidadeWebp = 90;

  /// Proporção típica de uma capa (largura / altura).
  static const double proporcaoTipica = 0.7;

  /// Arredondamento do tamanho decodificado: redimensionar a janela não
  /// decodifica a capa de novo a cada pixel.
  static const int passoDecodificacao = 64;

  /// Grava a capa escolhida na pasta de capas e devolve o caminho. No Windows
  /// copia o original; no Android e no Linux converte para WebP em até
  /// [larguraGravada]×[alturaGravada].
  static Future<String> gravar(PlatformFile arquivo) async {
    final original = await caminhoLocalDoArquivo(arquivo);
    final capasDir = await DbHelper().getCapasDirectory();

    final windows = !kIsWeb && Platform.isWindows;
    final extensao = windows ? p.extension(original) : '.webp';
    final destino =
        '${capasDir.path}/capa_${DateTime.now().millisecondsSinceEpoch}$extensao';

    if (windows) {
      await File(original).copy(destino);
    } else {
      final comprimida = await FlutterImageCompress.compressAndGetFile(
        original,
        destino,
        minWidth: larguraGravada,
        minHeight: alturaGravada,
        quality: qualidadeWebp,
        format: CompressFormat.webp,
      );
      if (comprimida == null) await File(original).copy(destino);
    }
    return destino;
  }

  /// Em quantos pixels decodificar a capa para um quadro de [largura]×[altura]
  /// pixels lógicos com `BoxFit.cover`, numa tela de [densidade]: o lado que
  /// preenche o quadro manda, e o outro segue a proporção da imagem.
  ///
  /// Quadro mais estreito que uma capa (o card no celular): a altura manda.
  /// Mais largo (card largo no computador): a largura manda. Decodificar no
  /// tamanho da tela deixa a capa nítida sem gastar memória à toa; o Flutter
  /// não aumenta uma imagem menor que isso.
  static ({int? largura, int? altura}) tamanhoDecodificado(
    double largura,
    double altura,
    double densidade,
  ) {
    int pixels(double logicos) => math.max(
      passoDecodificacao,
      (logicos * densidade / passoDecodificacao).ceil() * passoDecodificacao,
    );

    if (!largura.isFinite ||
        largura <= 0 ||
        largura / altura < proporcaoTipica) {
      return (largura: null, altura: pixels(altura));
    }
    return (largura: pixels(largura), altura: null);
  }
}
