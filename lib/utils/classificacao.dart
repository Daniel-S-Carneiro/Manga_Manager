import 'package:flutter/material.dart';

/// Tipo de leitura de um item da biblioteca (mangá, manhwa, novel...).
///
/// Fica na coluna `tipo` da tabela `mangas` pela [chave]; nulo é "sem tipo",
/// que é como começam os itens de antes da v3 do banco. A lista é fixa: o
/// que é pessoal de cada usuário vai nas tags.
class TipoLeitura {
  const TipoLeitura._(this.chave, this.nome, this.icone, this.cor);

  /// Valor gravado no banco. Não mude: os bancos e backups já têm essas.
  final String chave;

  /// Nome mostrado na tela.
  final String nome;
  final IconData icone;

  /// Fundo do selo no card, com texto branco por cima.
  final Color cor;

  static const manga = TipoLeitura._(
    'manga',
    'Mangá',
    Icons.auto_stories_rounded,
    Color(0xFF8E24AA),
  );
  static const manhwa = TipoLeitura._(
    'manhwa',
    'Manhwa',
    Icons.view_agenda_rounded,
    Color(0xFF00796B),
  );
  static const manhua = TipoLeitura._(
    'manhua',
    'Manhua',
    Icons.view_day_rounded,
    Color(0xFFC2185B),
  );
  static const webtoon = TipoLeitura._(
    'webtoon',
    'Webtoon',
    Icons.swipe_vertical_rounded,
    Color(0xFF3F51B5),
  );
  static const novel = TipoLeitura._(
    'novel',
    'Novel',
    Icons.article_rounded,
    Color(0xFF795548),
  );
  static const outro = TipoLeitura._(
    'outro',
    'Outro',
    Icons.category_rounded,
    Color(0xFF546E7A),
  );

  static const List<TipoLeitura> todos = [
    manga,
    manhwa,
    manhua,
    webtoon,
    novel,
    outro,
  ];

  /// Nome e ícone de quem não tem tipo.
  static const String nomeSemTipo = 'Sem tipo';
  static const IconData iconeSemTipo = Icons.help_outline_rounded;

  /// O tipo gravado no banco. Nulo para "sem tipo" e também para uma chave
  /// que esta versão não conhece (de uma versão mais nova do app).
  static TipoLeitura? daChave(String? chave) {
    for (final tipo in todos) {
      if (tipo.chave == chave) return tipo;
    }
    return null;
  }

  @override
  String toString() => 'TipoLeitura($chave)';
}

/// Status de leitura (coluna `status_leitura`, gravada pelo [valor]).
class StatusLeitura {
  const StatusLeitura._(this.valor, this.icone, this.cor);

  /// Valor gravado no banco e mostrado na tela.
  final String valor;
  final IconData icone;
  final Color cor;

  static const lendo = StatusLeitura._(
    'Lendo',
    Icons.menu_book_rounded,
    Color(0xFF2196F3),
  );
  static const completo = StatusLeitura._(
    'Completo',
    Icons.check_circle_rounded,
    Color(0xFF4CAF50),
  );
  static const dropado = StatusLeitura._(
    'Dropado',
    Icons.cancel_rounded,
    Color(0xFFF44336),
  );
  static const planejoLer = StatusLeitura._(
    'Planejo Ler',
    Icons.watch_later_rounded,
    Color(0xFFFF9800),
  );

  static const List<StatusLeitura> todos = [
    lendo,
    completo,
    dropado,
    planejoLer,
  ];

  /// O status gravado no banco, ou nulo se for um valor desconhecido.
  static StatusLeitura? doValor(String? valor) {
    for (final status in todos) {
      if (status.valor == valor) return status;
    }
    return null;
  }

  @override
  String toString() => 'StatusLeitura($valor)';
}

/// Filtro de tipo da lista principal: [todos], só os [semTipo] ou um tipo.
class FiltroTipo {
  const FiltroTipo._(this.tipo, this._semTipo);

  /// Só os itens de [tipo].
  const FiltroTipo.de(TipoLeitura this.tipo) : _semTipo = false;

  static const todos = FiltroTipo._(null, false);
  static const semTipo = FiltroTipo._(null, true);

  final TipoLeitura? tipo;
  final bool _semTipo;

  bool get ehTodos => tipo == null && !_semTipo;
  bool get ehSemTipo => _semTipo;

  String get nome => ehTodos
      ? 'Todos'
      : ehSemTipo
      ? TipoLeitura.nomeSemTipo
      : tipo!.nome;

  @override
  bool operator ==(Object other) =>
      other is FiltroTipo && other.tipo == tipo && other._semTipo == _semTipo;

  @override
  int get hashCode => Object.hash(tipo, _semTipo);

  @override
  String toString() => 'FiltroTipo($nome)';
}

/// O que a lista principal mostra: busca pelo nome, tipo e status.
class FiltroLista {
  const FiltroLista({
    this.busca = '',
    this.tipo = FiltroTipo.todos,
    this.status,
  });

  /// Trecho do nome em português ou em inglês.
  final String busca;
  final FiltroTipo tipo;

  /// Nulo mostra todos os status.
  final StatusLeitura? status;

  /// Algum filtro de tipo ou status ligado (a busca fica de fora).
  bool get temFiltro => !tipo.ehTodos || status != null;

  /// Mostra só parte da biblioteca (busca ou filtro).
  bool get restringe => busca.trim().isNotEmpty || temFiltro;

  FiltroLista copiarCom({
    String? busca,
    FiltroTipo? tipo,
    StatusLeitura? status,
    bool limparStatus = false,
  }) => FiltroLista(
    busca: busca ?? this.busca,
    tipo: tipo ?? this.tipo,
    status: limparStatus ? null : (status ?? this.status),
  );

  /// Mesma busca, sem filtro de tipo e status.
  FiltroLista semFiltros() => FiltroLista(busca: busca);

  /// Cláusula `WHERE` da tabela `mangas` (nula sem busca nem filtro). Cada
  /// parte vai entre parênteses: o `OR` da busca não pode escapar do `AND`.
  ({String? where, List<Object?> args}) clausula() {
    final partes = <String>[];
    final args = <Object?>[];

    final texto = busca.trim();
    if (texto.isNotEmpty) {
      partes.add('(nome_pt LIKE ? OR nome_en LIKE ?)');
      args.addAll(['%$texto%', '%$texto%']);
    }
    if (tipo.ehSemTipo) {
      // Também a chave que esta versão não conhece, que o card mostra como
      // sem tipo (TipoLeitura.daChave)
      final chaves = TipoLeitura.todos.map((t) => t.chave).toList();
      partes.add(
        '(tipo IS NULL OR tipo NOT IN '
        '(${List.filled(chaves.length, '?').join(', ')}))',
      );
      args.addAll(chaves);
    } else if (tipo.tipo != null) {
      partes.add('tipo = ?');
      args.add(tipo.tipo!.chave);
    }
    if (status != null) {
      partes.add('status_leitura = ?');
      args.add(status!.valor);
    }

    return (where: partes.isEmpty ? null : partes.join(' AND '), args: args);
  }

  @override
  bool operator ==(Object other) =>
      other is FiltroLista &&
      other.busca == busca &&
      other.tipo == tipo &&
      other.status == status;

  @override
  int get hashCode => Object.hash(busca, tipo, status);
}
