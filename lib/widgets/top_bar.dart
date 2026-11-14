import 'package:flutter/material.dart';
import 'package:onde_parei/utils/classificacao.dart';
import 'package:onde_parei/widgets/barra_filtros.dart';
import 'package:onde_parei/widgets/meu_db_viewer.dart';

class TopBar extends StatelessWidget {
  final bool showForm;
  final VoidCallback onToggleForm;
  final bool isDesktop;
  final VoidCallback onToggleTheme;
  final ValueChanged<String>? onSearchChanged;
  final FiltroLista filtro;
  final ValueChanged<FiltroLista> aoMudarFiltro;

  const TopBar({
    super.key,
    required this.showForm,
    required this.onToggleForm,
    required this.isDesktop,
    required this.onToggleTheme,
    required this.filtro,
    required this.aoMudarFiltro,
    this.onSearchChanged,
  });

  /// Com menos que isso a busca fica apertada demais, e os filtros descem
  /// para baixo dela. Cabe a lupa e o "Pesquisar...". Com 150, uma janela
  /// maximizada em 1920 px com escala de 150% ficava 2 px abaixo do limite.
  static const double _larguraMinimaDaBusca = 120;

  /// Tema (110) + Nova Leitura (150) + botão do banco (48) e três espaços de 12
  static const double _larguraDosBotoes = 344;

  /// Os filtros ficam na linha da busca quando, mesmo com as opções de nome
  /// mais longo escolhidas, sobra a largura mínima para a busca. A conta
  /// soma o espaço de 12 antes dos filtros e o de 4 depois deles.
  bool _filtrosCabemNaLinha(BuildContext context, double larguraDaBusca) =>
      larguraDaBusca >=
      _larguraMinimaDaBusca +
          12 +
          4 +
          BarraFiltros.larguraCompactaMaxima(context);

  Widget _filtros({required bool compacta}) =>
      BarraFiltros(filtro: filtro, aoMudar: aoMudarFiltro, compacta: compacta);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return isDesktop
        ? Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 200.0,
              vertical: 8.0,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) => _barraDoComputador(
                context,
                theme,
                // A borda de 4 da caixa ocupa 8 da largura
                naLinha: _filtrosCabemNaLinha(
                  context,
                  constraints.maxWidth - 8 - _larguraDosBotoes,
                ),
              ),
            ),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: LayoutBuilder(
              builder: (context, constraints) => _barraDoCelular(
                context,
                theme,
                naLinha: _filtrosCabemNaLinha(context, constraints.maxWidth),
              ),
            ),
          );
  }

  Widget _barraDoCelular(
    BuildContext context,
    ThemeData theme, {
    required bool naLinha,
  }) {
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 45,
                child: ElevatedButton.icon(
                  onPressed: onToggleTheme,
                  icon: const Text('🌗', style: TextStyle(fontSize: 14)),
                  label: const Text(
                    'Tema',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 45,
                child: ElevatedButton.icon(
                  onPressed: onToggleForm,
                  icon: Icon(
                    showForm ? Icons.remove : Icons.add,
                    color: colorScheme.secondary,
                    size: 18,
                  ),
                  label: Text(
                    showForm ? 'Fechar' : 'Nova Leitura',
                    maxLines: 1,
                    softWrap: false,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    foregroundColor: colorScheme.onSurface,
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: Icon(Icons.storage, color: colorScheme.tertiary),
              tooltip: 'Inspecionar Banco de Dados',
              onPressed: () => _abrirVisualizadorBanco(context),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 45,
          child: naLinha
              ? Row(
                  children: [
                    Expanded(child: _buildSearchField(theme)),
                    const SizedBox(width: 12),
                    _filtros(compacta: true),
                  ],
                )
              : _buildSearchField(theme),
        ),
        if (!naLinha) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: _filtros(compacta: false),
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  Widget _barraDoComputador(
    BuildContext context,
    ThemeData theme, {
    required bool naLinha,
  }) {
    final colorScheme = theme.colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 55,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border.all(color: colorScheme.surface, width: 4),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(12),
              bottom: Radius.circular(12),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 110,
                child: ElevatedButton.icon(
                  onPressed: onToggleTheme,
                  icon: const Text('🌗', style: TextStyle(fontSize: 14)),
                  label: const Text(
                    'Tema',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 150,
                child: ElevatedButton.icon(
                  onPressed: onToggleForm,
                  icon: Icon(
                    showForm ? Icons.remove : Icons.add,
                    color: colorScheme.secondary,
                    size: 18,
                  ),
                  label: Text(
                    showForm ? 'Fechar' : 'Nova Leitura',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    foregroundColor: colorScheme.onSurface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: Icon(Icons.storage, color: colorScheme.tertiary),
                tooltip: 'Inspecionar Banco de Dados',
                onPressed: () => _abrirVisualizadorBanco(context),
              ),
              const SizedBox(width: 12),
              Expanded(child: _buildSearchField(theme)),
              if (naLinha) ...[
                const SizedBox(width: 12),
                _filtros(compacta: true),
                const SizedBox(width: 4),
              ],
            ],
          ),
        ),
        if (!naLinha) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: _filtros(compacta: false),
          ),
        ],
      ],
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return TextField(
      onChanged: onSearchChanged,
      style: TextStyle(fontSize: 15, color: theme.colorScheme.onSurface),
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        hintText: 'Pesquisar...',
        hintStyle: TextStyle(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
        prefixIcon: Icon(
          Icons.search,
          size: 20,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        ),
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 12,
        ),
      ),
    );
  }

  Future<void> _abrirVisualizadorBanco(BuildContext context) async {
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const MeuDbViewer()),
      );
    }
  }
}
