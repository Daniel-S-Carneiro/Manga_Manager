/// Lista carregada aos lotes pela posição no banco (`LIMIT`/`OFFSET`), como a
/// da tela principal.
///
/// O [offset] é a posição no banco do próximo lote. Quando um item já
/// carregado sai do banco, todos os seguintes sobem uma posição; se o
/// [offset] não descer junto, o próximo lote começa um item adiante e esse
/// item nunca aparece (o "carregar mais" pulava um mangá depois de cada
/// exclusão). Por isso a remoção passa por [remover], e o desfazer por
/// [desfazerRemocao].
class ListaPaginada<T> {
  ListaPaginada({required this.tamanhoDoLote});

  final int tamanhoDoLote;
  final List<T> itens = [];

  /// Posição no banco do próximo lote.
  int offset = 0;

  /// Ainda há itens no banco depois dos carregados.
  bool temMais = true;

  /// Volta ao começo (nova busca, mangá novo, restauração).
  void reiniciar() {
    itens.clear();
    offset = 0;
    temMais = true;
  }

  /// Acrescenta o lote que veio do banco a partir do [offset].
  void acrescentarLote(List<T> lote) {
    itens.addAll(lote);
    offset += lote.length;
    if (lote.length < tamanhoDoLote) temMais = false;
  }

  /// Tira o item em [indice], que vai ser excluído do banco.
  ///
  /// O [offset] desce na hora, junto com a lista, e não depois que a
  /// exclusão terminar: o banco executa os comandos na ordem em que chegam,
  /// então um lote pedido depois daqui já encontra o banco sem o item.
  T remover(int indice) {
    final item = itens.removeAt(indice);
    if (offset > 0) offset--;
    return item;
  }

  /// Desfaz o [remover] quando a exclusão no banco falhou (o banco não
  /// mudou). Volta para [indice], ou para o fim se a lista encolheu.
  void desfazerRemocao(int indice, T item) {
    itens.insert(indice.clamp(0, itens.length), item);
    offset++;
  }
}
