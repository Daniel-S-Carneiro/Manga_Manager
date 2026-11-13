import 'dart:io' as io;

import 'package:flutter/material.dart';

import 'importar_manga_manager.dart';

/// Lista principal sem nenhuma leitura (sem busca nem filtro). Quem vem do
/// Manga Manager (o app com o nome antigo) traz a biblioteca dele por aqui:
/// no computador onde ele está ([bancoDoMangaManager]), direto do banco; nos
/// outros casos, pelo backup.
class BibliotecaVazia extends StatelessWidget {
  const BibliotecaVazia({super.key, this.bancoDoMangaManager});

  final io.File? bancoDoMangaManager;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cor = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    final banco = bancoDoMangaManager;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_rounded, size: 48, color: cor),
              const SizedBox(height: 12),
              Text(
                'Nenhuma leitura ainda. Adicione a primeira em '
                '"Nova Leitura".',
                textAlign: TextAlign.center,
                style: TextStyle(color: cor, fontSize: 16),
              ),
              const SizedBox(height: 24),
              if (banco != null) ...[
                Text(
                  'A biblioteca do Manga Manager está neste computador.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cor),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => importarDoMangaManager(context, banco),
                  icon: const Icon(Icons.drive_file_move_outline),
                  label: const Text('Importar do Manga Manager'),
                ),
              ] else
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text:
                            'Vindo do Manga Manager? Faça um backup nele e '
                            'restaure aqui: abra o ',
                      ),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Icon(
                          Icons.storage,
                          size: 18,
                          color: theme.colorScheme.tertiary,
                        ),
                      ),
                      const TextSpan(text: ' e use "Backup / Restaurar".'),
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cor),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
