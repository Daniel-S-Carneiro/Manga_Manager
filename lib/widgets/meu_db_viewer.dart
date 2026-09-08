import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_size/window_size.dart' as window_size;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';

class MeuDbViewer extends StatefulWidget {
  const MeuDbViewer({super.key});
  @override
  State<MeuDbViewer> createState() => _MeuDbViewerState();
}

class _MeuDbViewerState extends State<MeuDbViewer> {
  late Future<List<Map<String, dynamic>>> _mangaListFuture;
  late Future<Map<String, String>> _caminhosSistemaFuture;

  @override
  void initState() {
    super.initState();
    _mangaListFuture = DbHelper().getMangas(limit: 100, offset: 0);
    _caminhosSistemaFuture = _obterCaminhos();
  }

  Future<Map<String, String>> _obterCaminhos() async {
    if (kIsWeb) {
      return {
        'db': 'Navegador Web (IndexedDB / Memória)',
        'dir': 'Navegador Web (Sem diretório local físico acessível)',
      };
    }

    String dbPath = 'Desconhecido';
    String baseDir = 'Desconhecido';

    try {
      if (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        final directory = await getApplicationSupportDirectory();
        baseDir = directory.path;

        final String nomeDb = kDebugMode
            ? 'manga_manager_debug.db'
            : 'manga_manager.db';
        dbPath = p.join(directory.path, nomeDb);
      } else {
        baseDir = (await getApplicationDocumentsDirectory()).path;
        final dbDir = await getDatabasesPath();

        final String nomeDb = kDebugMode
            ? 'manga_manager_debug.db'
            : 'manga_manager.db';
        dbPath = p.join(dbDir, nomeDb);
      }
    } catch (e) {
      dbPath = 'Erro ao obter caminho: $e';
    }

    return {'db': dbPath, 'dir': baseDir};
  }

  void _redimensionarJanela(double largura, double altura) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
      window_size.setWindowMinSize(const Size(300, 400));
      window_size.setWindowMaxSize(const Size(4096, 4096));
      window_size.setWindowFrame(Rect.fromLTWH(100, 100, largura, altura));
    }
  }

  void _mostrarMenuSimuladorCelular(BuildContext context) {
    final TextEditingController larguraController = TextEditingController(
      text: '390',
    );
    final TextEditingController alturaController = TextEditingController(
      text: '844',
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: Text(
            'Simulador de Tela (Windows)',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 18,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Escolha um modelo pronto:',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                _botaoOpcaoCelular('iPhone Pequeno (SE)', 375, 667),
                _botaoOpcaoCelular('iPhone Maior (14/15 Pro Max)', 430, 932),
                _botaoOpcaoCelular('Android Pequeno (Compacto)', 360, 800),
                _botaoOpcaoCelular('Android Maior (Moderno/Gamer)', 412, 915),
                const Divider(height: 24),
                Text(
                  'Ou digite valores personalizados (X e Y):',
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: larguraController,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecor('Largura (X em pixels)'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: alturaController,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecor('Altura (Y em pixels)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final double? w = double.tryParse(larguraController.text);
                final double? h = double.tryParse(alturaController.text);
                if (w != null && h != null) {
                  _redimensionarJanela(w, h);
                }
                Navigator.pop(context);
              },
              child: const Text('Aplicar'),
            ),
          ],
        );
      },
    );
  }

  Widget _botaoOpcaoCelular(String nome, double w, double h) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
        onPressed: () {
          _redimensionarJanela(w, h);
          Navigator.pop(context);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '$nome\n(${w.toInt()} x ${h.toInt()})',
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecor(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: Theme.of(context).colorScheme.surface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
    isDense: true,
  );

  Widget _buildMiniatura(String? path) {
    if (path == null || path.isEmpty) {
      return const SizedBox(
        width: 50,
        height: 50,
        child: Icon(Icons.image_not_supported, color: Colors.grey),
      );
    }
    if (kIsWeb) {
      return const SizedBox(
        width: 50,
        height: 50,
        child: Icon(Icons.web, color: Colors.grey),
      );
    }

    final file = io.File(path);
    if (!file.existsSync()) {
      return const SizedBox(
        width: 50,
        height: 50,
        child: Icon(Icons.broken_image, color: Colors.red),
      );
    }
    return Image.file(
      file,
      width: 50,
      height: 50,
      fit: BoxFit.cover,
      cacheWidth: 100,
    );
  }

  void _mostrarDetalhesManga(Map<String, dynamic> manga) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(manga['nome_pt'] ?? 'Detalhes do Registro'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: manga.entries.map((entry) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.key.toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      SelectableText(
                        entry.value?.toString() ?? 'NULO',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const Divider(height: 10),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isWindowsApp =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 8,
        title: LayoutBuilder(
          builder: (context, constraints) {
            return Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth > 200
                        ? constraints.maxWidth - 100
                        : constraints.maxWidth,
                  ),
                  child: const Text(
                    'Inspetor de BD',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: kDebugMode ? Colors.orange : Colors.green,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    kDebugMode ? 'TESTE' : 'PROD',
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                  ),
                ),
              ],
            );
          },
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: Column(
        children: [
          if (isWindowsApp)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              child: Wrap(
                alignment: WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    icon: const Icon(Icons.phone_android, size: 16),
                    label: const Text('Simular Celular'),
                    onPressed: () => _mostrarMenuSimuladorCelular(context),
                  ),
                ],
              ),
            ),

          FutureBuilder<Map<String, String>>(
            future: _caminhosSistemaFuture,
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();

              final caminhos = snapshot.data!;
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: Theme.of(context).cardColor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CAMINHO DO BANCO DE DADOS:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    SelectableText(
                      caminhos['db']!,
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'DIRETÓRIO RAIZ DO APP:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    SelectableText(
                      caminhos['dir']!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              );
            },
          ),

          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _mangaListFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Text(
                      'Nenhum mangá encontrado.',
                      style: TextStyle(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  );
                }

                final lista = snapshot.data!;

                return ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: lista.length,
                  separatorBuilder: (_, _) =>
                      Divider(color: Theme.of(context).dividerColor),
                  itemBuilder: (context, index) {
                    final manga = lista[index];
                    return ListTile(
                      leading: _buildMiniatura(manga['capa_path']),
                      title: Text(
                        manga['nome_pt'] ?? 'Sem título',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        'Cap: ${manga['capitulo']} | ID: ${manga['id']}',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      trailing: const Icon(Icons.info_outline, size: 20),
                      onTap: () => _mostrarDetalhesManga(manga),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
