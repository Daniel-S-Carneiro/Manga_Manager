import 'package:flutter/foundation.dart';

import '../database/db_helper.dart';

/// Preferências da rolagem do mouse no leitor (painel aberto pela barra
/// flutuante), salvas na tabela `configuracoes`. O script que as aplica é o
/// `BrowserHelper.scriptRolagem`.
@immutable
class ConfigRolagem {
  /// false = o app não mexe na rolagem (fica a do navegador embutido).
  final bool ativa;

  /// Distância por giro da roda, em % de um navegador comum (100 = igual).
  final int intensidade;

  /// 0 = instantânea; cada nível deixa o deslize mais longo.
  final int suavidade;

  const ConfigRolagem({
    required this.ativa,
    required this.intensidade,
    required this.suavidade,
  });

  static const int intensidadeMinima = 10;
  static const int intensidadeMaxima = 300;
  static const int suavidadeMaxima = 10;

  static const ConfigRolagem padrao = ConfigRolagem(
    ativa: true,
    intensidade: 100,
    suavidade: 4,
  );

  static const String kAtiva = 'rolagem_ativa';
  static const String kIntensidade = 'rolagem_intensidade';
  static const String kSuavidade = 'rolagem_suavidade';

  /// Constante de tempo do deslize, em ms (0 = sem animação). A cada [tauMs]
  /// a página percorre ~63% do que falta.
  int get tauMs => suavidade * 25;

  /// Nome do nível de suavidade mostrado no painel.
  String get nomeSuavidade {
    if (suavidade == 0) return 'Desligada';
    if (suavidade <= 3) return 'Leve';
    if (suavidade <= 6) return 'Média';
    return 'Alta';
  }

  ConfigRolagem copyWith({bool? ativa, int? intensidade, int? suavidade}) {
    return ConfigRolagem(
      ativa: ativa ?? this.ativa,
      intensidade: intensidade ?? this.intensidade,
      suavidade: suavidade ?? this.suavidade,
    );
  }

  /// Valores como vêm do banco (texto). O que faltar ou vier inválido fica no
  /// [padrao]; número fora da faixa é trazido para dentro dela.
  factory ConfigRolagem.deTextos({
    String? ativa,
    String? intensidade,
    String? suavidade,
  }) {
    int numero(String? texto, int valorPadrao, int minimo, int maximo) {
      final v = int.tryParse(texto ?? '');
      if (v == null) return valorPadrao;
      if (v < minimo) return minimo;
      if (v > maximo) return maximo;
      return v;
    }

    return ConfigRolagem(
      ativa: ativa == null ? padrao.ativa : ativa == 'true',
      intensidade: numero(
        intensidade,
        padrao.intensidade,
        intensidadeMinima,
        intensidadeMaxima,
      ),
      suavidade: numero(suavidade, padrao.suavidade, 0, suavidadeMaxima),
    );
  }

  static Future<ConfigRolagem> carregar() async {
    final db = DbHelper();
    return ConfigRolagem.deTextos(
      ativa: await db.getConfig(kAtiva),
      intensidade: await db.getConfig(kIntensidade),
      suavidade: await db.getConfig(kSuavidade),
    );
  }

  Future<void> salvar() async {
    final db = DbHelper();
    await db.setConfig(kAtiva, ativa.toString());
    await db.setConfig(kIntensidade, intensidade.toString());
    await db.setConfig(kSuavidade, suavidade.toString());
  }

  @override
  bool operator ==(Object other) =>
      other is ConfigRolagem &&
      other.ativa == ativa &&
      other.intensidade == intensidade &&
      other.suavidade == suavidade;

  @override
  int get hashCode => Object.hash(ativa, intensidade, suavidade);

  @override
  String toString() =>
      'ConfigRolagem(ativa: $ativa, intensidade: $intensidade%, '
      'suavidade: $suavidade)';
}
