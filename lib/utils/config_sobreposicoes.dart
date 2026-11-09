import 'dart:convert';

import '../database/db_helper.dart';

/// Sites em que o usuário desligou, pelo botão da barra do leitor, a regra que
/// esconde avisos por cima da página (ver `BrowserHelper.getAdBlockScript`,
/// `removerSobreposicoes`). Fica na chave [chave] como lista JSON de domínios
/// (sem o "www.", ver `BrowserHelper.dominioDoSite`). A regra vem ligada.
class ConfigSobreposicoes {
  static const String chave = 'sobreposicoes_desligadas';

  /// Lista gravada; texto vazio ou inválido vira lista vazia.
  static List<String> decodificar(String? texto) {
    if (texto == null || texto.isEmpty) return [];
    try {
      final valor = jsonDecode(texto);
      if (valor is! List) return [];
      return valor
          .whereType<String>()
          .map((s) => s.trim().toLowerCase())
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Lista nova depois de ligar ([ativa] = true) ou desligar a regra em
  /// [dominio]. Sem repetições e em ordem, para gravar sempre igual.
  static List<String> atualizar(
    List<String> desligados,
    String dominio, {
    required bool ativa,
  }) {
    final d = dominio.trim().toLowerCase();
    final conjunto = {...desligados.map((e) => e.trim().toLowerCase())};
    if (d.isNotEmpty) {
      if (ativa) {
        conjunto.remove(d);
      } else {
        conjunto.add(d);
      }
    }
    return conjunto.toList()..sort();
  }

  static Future<bool> ativaNoSite(String dominio) async {
    final lista = decodificar(await DbHelper().getConfig(chave));
    return !lista.contains(dominio.trim().toLowerCase());
  }

  static Future<void> definir(String dominio, {required bool ativa}) async {
    final db = DbHelper();
    final lista = atualizar(
      decodificar(await db.getConfig(chave)),
      dominio,
      ativa: ativa,
    );
    await db.setConfig(chave, jsonEncode(lista));
  }
}
