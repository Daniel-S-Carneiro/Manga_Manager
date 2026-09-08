import 'package:flutter/material.dart';
import 'package:manga_manager/widgets/meu_db_viewer.dart';

class TopBar extends StatelessWidget {
  final bool showForm;
  final VoidCallback onToggleForm;
  final bool isDesktop;
  final VoidCallback onToggleTheme;
  final ValueChanged<String>? onSearchChanged;

  const TopBar({
    super.key,
    required this.showForm,
    required this.onToggleForm,
    required this.isDesktop,
    required this.onToggleTheme,
    this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!isDesktop) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
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
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
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
                        showForm ? 'Fechar' : 'Novo Mangá',
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
            SizedBox(height: 45, child: _buildSearchField(theme)),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 200.0, vertical: 8.0),
      child: Container(
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
                  showForm ? 'Fechar' : 'Novo Mangá',
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
          ],
        ),
      ),
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
