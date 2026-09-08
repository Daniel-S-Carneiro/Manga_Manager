import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_size/window_size.dart' as window_size;
import '../database/db_helper.dart';

class MeuDbViewer extends StatefulWidget {
  const MeuDbViewer({super.key});
  @override
  State<MeuDbViewer> createState() => _MeuDbViewerState();
}

class _MeuDbViewerState extends State<MeuDbViewer> {
  late Future<List<Map<String, dynamic>>> _mangaListFuture;
  late Future<Map<String, String>> _caminhosSistemaFuture;

  String _installedVersion = '...';
  String _latestGitVersion = 'Carregando...';
  bool _hasUpdate = false;
  bool _checkingUpdate = true;
  String? _downloadUrl;
  static const String _gitApiUrl =
      'https://api.github.com/repos/Daniel-S-Carneiro/Manga_Manager/releases/latest';

  @override
  void initState() {
    super.initState();
    _mangaListFuture = DbHelper().getMangas(limit: 100, offset: 0);
    _caminhosSistemaFuture = _obterCaminhos();
    _verificarVersaoGit();
  }

  Future<void> _verificarVersaoGit() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final current = packageInfo.version;

      final response = await http.get(
        Uri.parse(_gitApiUrl),
        headers: {'Accept': 'application/vnd.github+json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final String latestTag = (data['tag_name'] as String)
            .replaceAll('v', '')
            .trim();
        final List<dynamic> assets = data['assets'] ?? [];

        final isNewer = _isNewerVersion(current, latestTag);
        final download = _getAssetUrlForPlatform(assets);

        if (mounted) {
          setState(() {
            _installedVersion = current;
            _latestGitVersion = latestTag;
            _hasUpdate = isNewer;
            _downloadUrl = download;
            _checkingUpdate = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _installedVersion = current;
            _latestGitVersion = 'Indisponível';
            _checkingUpdate = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _latestGitVersion = 'Erro na busca';
          _checkingUpdate = false;
        });
      }
    }
  }

  bool _isNewerVersion(String current, String latest) {
    final c = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final l = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < l.length; i++) {
      final currentPart = i < c.length ? c[i] : 0;
      if (l[i] > currentPart) return true;
      if (l[i] < currentPart) return false;
    }
    return false;
  }

  String? _getAssetUrlForPlatform(List<dynamic> assets) {
    if (kIsWeb) return null;
    String targetExtension = '';
    if (io.Platform.isAndroid) {
      targetExtension = '.apk';
    } else if (io.Platform.isWindows) {
      targetExtension = '.exe';
    } else if (io.Platform.isLinux) {
      targetExtension = '.tar.gz';
    }

    for (final asset in assets) {
      final String name = asset['name'] ?? '';
      if (name.endsWith(targetExtension)) {
        return asset['browser_download_url'] as String?;
      }
    }
    return null;
  }

  Future<void> _baixarEAtualizarAutomaticamente() async {
    if (_downloadUrl == null) return;

    // Fecha o diálogo de informações de versão
    Navigator.pop(context);

    // Mostra um diálogo de progresso informando o download
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(
              child: Text(
                'Baixando e aplicando atualização em segundo plano...',
              ),
            ),
          ],
        ),
      ),
    );

    try {
      final tempDir = await getTemporaryDirectory();
      if (!mounted) return;

      final filePath = p.join(tempDir.path, 'manga_manager_update.exe');

      // Baixa o arquivo do instalador do GitHub
      final response = await http.get(Uri.parse(_downloadUrl!));
      if (!mounted) return;

      if (response.statusCode == 200) {
        final file = io.File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        if (!mounted) return;

        if (io.Platform.isWindows) {
          await io.Process.start(filePath, [
            '/S',
          ], mode: io.ProcessStartMode.detached);
          io.exit(0);
        } else {
          Navigator.pop(context); // Fecha o loading
          final uri = Uri.parse(_downloadUrl!);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
      } else {
        Navigator.pop(context); // Fecha o loading
        _mostrarErroDialog('Falha ao baixar o arquivo de atualização.');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Fecha o loading
      _mostrarErroDialog('Erro ao executar a atualização: $e');
    }
  }

  void _mostrarErroDialog(String mensagem) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Erro na Atualização'),
        content: Text(mensagem),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoVersao(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                _hasUpdate ? Icons.warning_amber_rounded : Icons.check_circle,
                color: _hasUpdate ? Colors.red : Colors.green,
              ),
              const SizedBox(width: 8),
              const Text('Informações de Versão'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _itemInfoDialog('Versão Instalada:', 'v$_installedVersion'),
                const SizedBox(height: 8),
                _itemInfoDialog('Última Versão no Git:', 'v$_latestGitVersion'),
                const SizedBox(height: 12),
                Text(
                  'URL DE PESQUISA DO GIT:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  _gitApiUrl,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (_hasUpdate ? Colors.red : Colors.green).withValues(
                      alpha: 0.1,
                    ),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _hasUpdate ? Colors.red : Colors.green,
                    ),
                  ),
                  child: Text(
                    _hasUpdate
                        ? 'Existe uma nova atualização disponível!'
                        : 'Você já está utilizando a versão mais recente.',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: _hasUpdate ? Colors.red : Colors.green,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fechar'),
            ),
            if (_hasUpdate && _downloadUrl != null)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.system_update, size: 16),
                label: const Text('Atualizar Automaticamente'),
                onPressed: () => _baixarEAtualizarAutomaticamente(),
              ),
          ],
        );
      },
    );
  }

  Widget _itemInfoDialog(String titulo, String valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        Text(
          valor,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ],
    );
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
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _checkingUpdate
                          ? Colors.grey
                          : (_hasUpdate ? Colors.red : Colors.green),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    icon: _checkingUpdate
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            _hasUpdate
                                ? Icons.system_update
                                : Icons.check_circle,
                            size: 16,
                          ),
                    label: Text('v$_installedVersion'),
                    onPressed: () => _mostrarDialogoVersao(context),
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
