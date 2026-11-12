import 'package:flutter/material.dart';

import '../utils/classificacao.dart';

/// Filtros da lista principal (tipo e status), abaixo da busca.
///
/// Só monta o [FiltroLista] novo e entrega em [aoMudar]; quem recarrega a
/// lista é a tela.
class BarraFiltros extends StatelessWidget {
  const BarraFiltros({super.key, required this.filtro, required this.aoMudar});

  final FiltroLista filtro;
  final ValueChanged<FiltroLista> aoMudar;

  static const List<FiltroTipo> _opcoesDeTipo = [
    FiltroTipo.todos,
    FiltroTipo.semTipo,
    FiltroTipo.de(TipoLeitura.manga),
    FiltroTipo.de(TipoLeitura.manhwa),
    FiltroTipo.de(TipoLeitura.manhua),
    FiltroTipo.de(TipoLeitura.webtoon),
    FiltroTipo.de(TipoLeitura.novel),
    FiltroTipo.de(TipoLeitura.outro),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _MenuDoFiltro(
          rotulo: 'Tipo',
          valorAtual: filtro.tipo.nome,
          ativo: !filtro.tipo.ehTodos,
          itens: [
            for (final opcao in _opcoesDeTipo)
              _ItemDoFiltro(
                nome: opcao.nome,
                icone: opcao.ehTodos
                    ? Icons.apps_rounded
                    : opcao.ehSemTipo
                    ? TipoLeitura.iconeSemTipo
                    : opcao.tipo!.icone,
                cor: opcao.tipo?.cor ?? colorScheme.onSurfaceVariant,
                marcado: opcao == filtro.tipo,
              ),
          ],
          aoEscolher: (i) {
            final tipo = _opcoesDeTipo[i];
            if (tipo != filtro.tipo) aoMudar(filtro.copiarCom(tipo: tipo));
          },
        ),
        _MenuDoFiltro(
          rotulo: 'Status',
          valorAtual: filtro.status?.valor ?? 'Todos',
          ativo: filtro.status != null,
          itens: [
            _ItemDoFiltro(
              nome: 'Todos',
              icone: Icons.apps_rounded,
              cor: colorScheme.onSurfaceVariant,
              marcado: filtro.status == null,
            ),
            for (final status in StatusLeitura.todos)
              _ItemDoFiltro(
                nome: status.valor,
                icone: status.icone,
                cor: status.cor,
                marcado: status == filtro.status,
              ),
          ],
          aoEscolher: (i) {
            // Posição 0 é "Todos"
            final status = i == 0 ? null : StatusLeitura.todos[i - 1];
            if (status == filtro.status) return;
            aoMudar(
              status == null
                  ? filtro.copiarCom(limparStatus: true)
                  : filtro.copiarCom(status: status),
            );
          },
        ),
        if (filtro.temFiltro)
          TextButton.icon(
            onPressed: () => aoMudar(filtro.semFiltros()),
            icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
            label: const Text('Limpar filtros'),
          ),
      ],
    );
  }
}

class _ItemDoFiltro {
  const _ItemDoFiltro({
    required this.nome,
    required this.icone,
    required this.cor,
    required this.marcado,
  });

  final String nome;
  final IconData icone;
  final Color cor;
  final bool marcado;
}

/// Botão em forma de etiqueta ("Tipo: Manhwa") que abre o menu do filtro.
/// O menu trabalha pela posição do item (veja SeletorMenu).
class _MenuDoFiltro extends StatelessWidget {
  const _MenuDoFiltro({
    required this.rotulo,
    required this.valorAtual,
    required this.ativo,
    required this.itens,
    required this.aoEscolher,
  });

  final String rotulo;
  final String valorAtual;
  final bool ativo;
  final List<_ItemDoFiltro> itens;
  final ValueChanged<int> aoEscolher;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final corDoTexto = ativo
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;

    return PopupMenuButton<int>(
      tooltip: 'Filtrar por ${rotulo.toLowerCase()}',
      color: colorScheme.surfaceContainer,
      position: PopupMenuPosition.under,
      onSelected: aoEscolher,
      itemBuilder: (context) => [
        for (var i = 0; i < itens.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Row(
              children: [
                Icon(itens[i].icone, color: itens[i].cor, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    itens[i].nome,
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                ),
                if (itens[i].marcado)
                  Icon(Icons.check_rounded, color: colorScheme.primary),
              ],
            ),
          ),
      ],
      child: Container(
        height: 36,
        padding: const EdgeInsets.only(left: 12, right: 6),
        decoration: BoxDecoration(
          color: ativo
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: ativo
                ? colorScheme.primary
                : colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$rotulo: ',
              style: TextStyle(
                color: corDoTexto.withValues(alpha: 0.7),
                fontSize: 13,
              ),
            ),
            Text(
              valorAtual,
              style: TextStyle(
                color: corDoTexto,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            Icon(Icons.arrow_drop_down, color: corDoTexto, size: 20),
          ],
        ),
      ),
    );
  }
}
