import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import '../database/db_helper.dart';
import 'mobile_simulator_button.dart';
import 'version_updater_button.dart';
import 'backup_manager_button.dart';

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
    _recarregarLista(); // Centralizamos a chamada
    _caminhosSistemaFuture = _obterCaminhos();
  }

  // Nova função para podermos chamar quando o backup for restaurado
  void _recarregarLista() {
    setState(() {
      _mangaListFuture = DbHelper().getMangas(limit: 100, offset: 0);
    });
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
                    kDebugMode ? 'DEV' : 'PROD',
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
          // A BARRA COM OS COMPONENTES AGORA NÃO DEPENDE SÓ DO WINDOWS PARA O BACKUP APARECER
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
                if (isWindowsApp) const MobileSimulatorButton(),
                const VersionUpdaterButton(),
                // NOVO COMPONENTE AQUI
                BackupManagerButton(
                  onBackupRestored:
                      _recarregarLista, // Chama a função para dar refresh na UI
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
