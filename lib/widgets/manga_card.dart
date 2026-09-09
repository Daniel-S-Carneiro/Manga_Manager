import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../database/db_helper.dart';
import '../screens/browser_screen.dart';
import 'edit_manga_form.dart';

class MangaCardWidget extends StatelessWidget {
  final Map<String, dynamic> manga;
  final VoidCallback onDelete;
  final VoidCallback onUpdate;

  const MangaCardWidget({
    super.key,
    required this.manga,
    required this.onDelete,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.cardColor,
      elevation: 2,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: theme.colorScheme.onSurface.withValues(
            alpha: 0.1,
          ), // Borda sutil
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 320,
            child: Stack(
              children: [
                _buildCapa(context),
                Positioned(top: 8, left: 8, child: _buildStatusTag()),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment
                    .spaceBetween, // Mantém o capítulo preso embaixo
                children: [
                  // Usamos Flexible para o bloco de texto ocupar o espaço com segurança sem estourar
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          manga['nome_pt'] ?? 'Sem nome',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                            fontSize: 17,
                            height: 1.2,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          manga['nome_en'] ?? '',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                            fontSize: 13,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Capítulo travado firmemente logo acima do rodapé
                  Text(
                    'Capítulo: ${manga['capitulo'] ?? 0}',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40, // Altura fixa padronizada
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () => _abrirLink(context),
                      child: const Text(
                        'Ler',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height:
                      40, // Mesma altura fixa para alinhar com o botão "Ler"
                  width: 40,
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.05,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      padding: EdgeInsets
                          .zero, // Remove o padding interno padrão para centralizar o ícone
                      icon: const Icon(
                        Icons.edit,
                        color: Colors.amber,
                        size: 20,
                      ),
                      onPressed: () => _editarManga(context),
                      tooltip: 'Editar',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _editarManga(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 768;

    if (isDesktop) {
      showDialog(
        context: context,
        barrierColor: Colors.transparent,
        builder: (context) => GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            color: Colors.black54,
            child: Center(
              child: GestureDetector(
                onTap: () {},
                child: EditMangaFormWidget(
                  manga: manga,
                  onMangaUpdated: onUpdate,
                  onDelete: onDelete,
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            children: [
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24.0),
                  child: EditMangaFormWidget(
                    manga: manga,
                    onMangaUpdated: onUpdate,
                    onDelete: onDelete,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildCapa(BuildContext context) {
    final String? capaPath = manga['capa_path'];
    if (capaPath == null || capaPath.isEmpty || kIsWeb) {
      return _placeholderCapa(context);
    }

    return Image.file(
      File(capaPath),
      width: double.infinity,
      height: 320,
      fit: BoxFit.cover,
      cacheWidth: 400,
      errorBuilder: (context, error, stackTrace) => _placeholderCapa(context),
    );
  }

  Widget _placeholderCapa(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.onSurface.withValues(
        alpha: 0.05,
      ), // Fundo dinâmico
      child: Center(
        child: Icon(
          Icons.image_not_supported,
          color: theme.colorScheme.onSurface.withValues(
            alpha: 0.3,
          ), // Ícone dinâmico
          size: 40,
        ),
      ),
    );
  }

  Widget _buildStatusTag() {
    final String status = manga['status_leitura'] ?? 'Lendo';
    Color bgColor;

    switch (status) {
      case 'Completo':
        bgColor = const Color(0xFF4CAF50);
        break;
      case 'Dropado':
        bgColor = const Color(0xFFF44336);
        break;
      case 'Planejo Ler':
        bgColor = const Color(0xFFFF9800);
        break;
      case 'Lendo':
      default:
        bgColor = const Color(0xFF2196F3);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Text(
        status.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Future<void> _abrirLink(BuildContext context) async {
    final String? urlString = manga['link_url'];
    if (urlString == null || urlString.trim().isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro: O link deste mangá está vazio.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    String urlFinal = urlString.trim();
    if (!urlFinal.startsWith('http://') && !urlFinal.startsWith('https://')) {
      urlFinal = 'https://$urlFinal';
    }

    try {
      final String? novoLink = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => BrowserScreen(
            initialUrl: urlFinal,
            mangaTitle: manga['nome_pt'] ?? 'Leitor',
          ),
        ),
      );

      if (!context.mounted) return;

      if (novoLink != null && novoLink.isNotEmpty && novoLink != urlString) {
        final bool? confirmar = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Atualizar Link / Capítulo?'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'A página final antes de fechar o leitor é diferente da inicial. Deseja salvar este novo link para o mangá?',
                ),
                const SizedBox(height: 12),
                Text(
                  novoLink,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Manter Anterior'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Atualizar'),
              ),
            ],
          ),
        );

        if (confirmar == true) {
          final id = manga['id'];
          if (id != null) {
            await DbHelper().updateManga(id, {'link_url': novoLink});
            onUpdate();
          }
        }
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao carregar o leitor: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
