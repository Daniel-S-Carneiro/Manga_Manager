import 'package:flutter/material.dart';

/// O que mudou entre o mangá salvo e o que o leitor devolveu ao fechar.
/// Campo null = sem mudança.
class MudancasLeitura {
  final String? novoLink;
  final int? novoCap;

  const MudancasLeitura({this.novoLink, this.novoCap});

  bool get vazia => novoLink == null && novoCap == null;

  /// [resultado] é o valor do Navigator.pop do leitor: Map {'url', 'capitulo'}
  /// (BrowserScreen) ou só a URL (LinuxBrowserScreen).
  factory MudancasLeitura.calcular({
    required Object? resultado,
    required String? linkSalvo,
    required int? capSalvo,
  }) {
    String? link;
    int? cap;

    if (resultado is Map) {
      final u = resultado['url'];
      if (u is String) link = u;
      final c = resultado['capitulo'];
      if (c is num) cap = c.toInt();
    } else if (resultado is String) {
      link = resultado;
    }

    String? novoLink;
    if (link != null && link.trim().isNotEmpty) {
      final l = link.trim();
      if (linkSalvo == null || normalizarLink(l) != normalizarLink(linkSalvo)) {
        novoLink = l;
      }
    }

    // Capítulo igual ao salvo não é mudança
    final int? novoCap = (cap != null && cap > 0 && cap != capSalvo)
        ? cap
        : null;

    return MudancasLeitura(novoLink: novoLink, novoCap: novoCap);
  }

  /// Ignora diferenças que não mudam a página: espaços, o "https://" que o
  /// card acrescenta ao abrir e "/" no final.
  static String normalizarLink(String url) {
    var u = url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }
}

/// O que o usuário marcou para salvar.
typedef EscolhaAtualizacao = ({bool salvarLink, bool salvarCap});

/// Pergunta o que salvar. Nada é gravado sem confirmação, porque a detecção do
/// capítulo pode errar (ex.: página com a lista de capítulos).
/// Capítulo menor que o salvo vem desmarcado (releitura não perde o progresso).
/// Retorna null se o usuário mantiver os dados anteriores.
Future<EscolhaAtualizacao?> confirmarAtualizacaoLeitura(
  BuildContext context, {
  required MudancasLeitura mudancas,
  required int? capSalvo,
}) {
  final novoLink = mudancas.novoLink;
  final novoCap = mudancas.novoCap;
  final bool capMenor =
      novoCap != null && capSalvo != null && novoCap < capSalvo;

  bool salvarLink = novoLink != null;
  bool salvarCap = novoCap != null && !capMenor;

  return showDialog<EscolhaAtualizacao>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        // Rola em telas pequenas (link longo + aviso não cabem em 320x640)
        scrollable: true,
        title: const Text('Atualizar Link / Capítulo?'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'O leitor terminou numa página diferente da salva. Marque o que deseja atualizar:',
              ),
              const SizedBox(height: 8),
              if (novoLink != null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: salvarLink,
                  onChanged: (v) =>
                      setDialogState(() => salvarLink = v ?? false),
                  title: const Text('Link'),
                  subtitle: Text(
                    novoLink,
                    style: const TextStyle(fontSize: 12),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (novoCap != null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: salvarCap,
                  onChanged: (v) =>
                      setDialogState(() => salvarCap = v ?? false),
                  title: Text('Capítulo: ${capSalvo ?? '-'} → $novoCap'),
                  subtitle: capMenor
                      ? const Text(
                          'Menor que o capítulo salvo. Confira antes de marcar.',
                        )
                      : null,
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Manter Anterior'),
          ),
          ElevatedButton(
            onPressed: (salvarLink || salvarCap)
                ? () => Navigator.pop(ctx, (
                    salvarLink: salvarLink,
                    salvarCap: salvarCap,
                  ))
                : null,
            child: const Text('Atualizar'),
          ),
        ],
      ),
    ),
  );
}
