import 'package:flutter/material.dart';

import '../utils/classificacao.dart';

/// Uma opção do [SeletorMenu].
class OpcaoMenu<T> {
  const OpcaoMenu({
    required this.valor,
    required this.nome,
    required this.icone,
    required this.cor,
  });

  final T valor;
  final String nome;
  final IconData icone;
  final Color cor;
}

/// Opções do tipo nos formulários: "Sem tipo" (valor nulo) e os tipos, pela
/// chave do banco.
final List<OpcaoMenu<String?>> opcoesDeTipo = [
  const OpcaoMenu(
    valor: null,
    nome: TipoLeitura.nomeSemTipo,
    icone: TipoLeitura.iconeSemTipo,
    cor: Colors.grey,
  ),
  for (final tipo in TipoLeitura.todos)
    OpcaoMenu(
      valor: tipo.chave,
      nome: tipo.nome,
      icone: tipo.icone,
      cor: tipo.cor,
    ),
];

/// Opções do status nos formulários, pelo valor do banco.
final List<OpcaoMenu<String>> opcoesDeStatus = [
  for (final status in StatusLeitura.todos)
    OpcaoMenu(
      valor: status.valor,
      nome: status.valor,
      icone: status.icone,
      cor: status.cor,
    ),
];

/// Campo de escolha dos formulários (tipo e status), com o visual dos
/// campos de texto.
///
/// O menu trabalha pela posição da opção, e não pelo valor: o
/// `PopupMenuButton` trata um valor nulo como "fechou sem escolher", e
/// "Sem tipo" é nulo. Um [selecionado] que não está nas opções (chave de
/// uma versão mais nova) aparece como a primeira opção e só muda se o
/// usuário escolher outra.
class SeletorMenu<T> extends StatelessWidget {
  const SeletorMenu({
    super.key,
    required this.rotulo,
    required this.opcoes,
    required this.selecionado,
    required this.aoSelecionar,
  });

  final String rotulo;
  final List<OpcaoMenu<T>> opcoes;
  final T selecionado;
  final ValueChanged<T> aoSelecionar;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final indice = opcoes.indexWhere((o) => o.valor == selecionado);
    final atual = opcoes[indice < 0 ? 0 : indice];

    return LayoutBuilder(
      builder: (context, constraints) => PopupMenuButton<int>(
        initialValue: indice < 0 ? null : indice,
        tooltip: rotulo,
        color: colorScheme.surfaceContainer,
        position: PopupMenuPosition.under,
        // Menu da largura do campo
        constraints: constraints.hasBoundedWidth
            ? BoxConstraints.tightFor(width: constraints.maxWidth)
            : null,
        onSelected: (i) => aoSelecionar(opcoes[i].valor),
        itemBuilder: (context) => [
          for (var i = 0; i < opcoes.length; i++)
            PopupMenuItem<int>(
              value: i,
              child: Row(
                children: [
                  Icon(opcoes[i].icone, color: opcoes[i].cor, size: 20),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      opcoes[i].nome,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
        ],
        child: InputDecorator(
          isEmpty: false,
          decoration: InputDecoration(
            labelText: rotulo,
            labelStyle: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.7),
              fontSize: 16,
            ),
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.5,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                color: colorScheme.outline.withValues(alpha: 0.3),
              ),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
          ),
          child: Row(
            children: [
              Icon(atual.icone, color: atual.cor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  atual.nome,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colorScheme.onSurface, fontSize: 16),
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
