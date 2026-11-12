import 'package:flutter_test/flutter_test.dart';
import 'package:manga_manager/utils/lista_paginada.dart';

/// Banco falso com a regra do `LIMIT`/`OFFSET` do `DbHelper.getMangas`: a
/// página sai das linhas que existem na hora da consulta, em ordem.
class _BancoFalso {
  _BancoFalso(int total) : linhas = List.generate(total, (i) => i + 1);

  final List<int> linhas;

  List<int> pagina(int limite, int offset) =>
      linhas.skip(offset).take(limite).toList();

  void excluir(int id) => linhas.remove(id);
}

void main() {
  /// Carrega lotes até acabar, como a rolagem da tela principal
  void carregarTudo(ListaPaginada<int> lista, _BancoFalso banco) {
    while (lista.temMais) {
      lista.acrescentarLote(banco.pagina(lista.tamanhoDoLote, lista.offset));
    }
  }

  /// Exclusão como a do card: tira da lista e depois do banco
  void excluir(ListaPaginada<int> lista, _BancoFalso banco, int id) {
    lista.remover(lista.itens.indexOf(id));
    banco.excluir(id);
  }

  test('excluir antes do próximo lote não pula nenhum mangá', () {
    final banco = _BancoFalso(35);
    final lista = ListaPaginada<int>(tamanhoDoLote: 30);
    lista.acrescentarLote(banco.pagina(30, lista.offset));

    excluir(lista, banco, 10);
    carregarTudo(lista, banco);

    // Antes da correção o 31 nunca aparecia
    expect(lista.itens, [for (var i = 1; i <= 35; i++) i]..remove(10));
    expect(lista.temMais, isFalse);
  });

  test('várias exclusões entre os lotes', () {
    final banco = _BancoFalso(100);
    final lista = ListaPaginada<int>(tamanhoDoLote: 30);

    lista.acrescentarLote(banco.pagina(30, lista.offset));
    for (final id in [1, 15, 30]) {
      excluir(lista, banco, id);
    }
    lista.acrescentarLote(banco.pagina(30, lista.offset));
    for (final id in [31, 60]) {
      excluir(lista, banco, id);
    }
    carregarTudo(lista, banco);

    expect(lista.itens, banco.linhas);
    expect(lista.itens.toSet(), hasLength(lista.itens.length));
    expect(lista.itens, hasLength(95));
  });

  test('exclusão que falhou volta para o lugar e não muda o próximo lote', () {
    final banco = _BancoFalso(35);
    final lista = ListaPaginada<int>(tamanhoDoLote: 30);
    lista.acrescentarLote(banco.pagina(30, lista.offset));

    // O banco recusou: o item volta e o banco continua igual
    final item = lista.remover(9);
    lista.desfazerRemocao(9, item);
    expect(lista.itens, [for (var i = 1; i <= 30; i++) i]);
    expect(lista.offset, 30);

    carregarTudo(lista, banco);
    expect(lista.itens, [for (var i = 1; i <= 35; i++) i]);
  });

  test('exclusão enquanto um lote ainda está chegando', () {
    final banco = _BancoFalso(100);
    final lista = ListaPaginada<int>(tamanhoDoLote: 30);
    lista.acrescentarLote(banco.pagina(30, lista.offset));

    // O banco responde ao lote antes de executar a exclusão, que só chega
    // na lista depois
    final aCaminho = banco.pagina(30, lista.offset);
    excluir(lista, banco, 10);
    lista.acrescentarLote(aCaminho);
    carregarTudo(lista, banco);

    expect(lista.itens, [for (var i = 1; i <= 100; i++) i]..remove(10));
  });

  test('desfazer depois que a lista encolheu não sai dos limites', () {
    final lista = ListaPaginada<int>(tamanhoDoLote: 30)
      ..acrescentarLote([1, 2, 3]);
    final item = lista.remover(2);
    lista.remover(0);
    lista.desfazerRemocao(2, item);
    expect(lista.itens, [2, 3]);
  });

  test('lote pedido antes de reiniciar é descartado', () {
    final banco = _BancoFalso(100);
    final lista = ListaPaginada<int>(tamanhoDoLote: 30);
    lista.acrescentarLote(banco.pagina(30, lista.offset));

    // Filtro trocado enquanto o segundo lote chegava
    final geracaoAntiga = lista.geracao;
    final aCaminho = banco.pagina(30, lista.offset);
    lista.reiniciar();
    expect(lista.acrescentarLote(aCaminho, geracao: geracaoAntiga), isFalse);
    expect(lista.itens, isEmpty);
    expect(lista.offset, 0);
    expect(lista.temMais, isTrue);

    // O lote da lista nova entra
    final geracao = lista.geracao;
    expect(
      lista.acrescentarLote(banco.pagina(30, lista.offset), geracao: geracao),
      isTrue,
    );
    expect(lista.itens, [for (var i = 1; i <= 30; i++) i]);
  });

  test('item que deixou de combinar com o filtro sai como uma exclusão', () {
    // Banco com o filtro aplicado: o item 10 deixou de combinar
    final filtrado = _BancoFalso(35);
    final lista = ListaPaginada<int>(tamanhoDoLote: 30);
    lista.acrescentarLote(filtrado.pagina(30, lista.offset));

    filtrado.excluir(10);
    lista.remover(lista.itens.indexOf(10));
    carregarTudo(lista, filtrado);

    expect(lista.itens, [for (var i = 1; i <= 35; i++) i]..remove(10));
  });

  test('reiniciar volta ao começo', () {
    final lista = ListaPaginada<int>(tamanhoDoLote: 2)
      ..acrescentarLote([1])
      ..reiniciar();
    expect(lista.itens, isEmpty);
    expect(lista.offset, 0);
    expect(lista.temMais, isTrue);
  });
}
