import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  static const String _repoOwner = 'Daniel-S-Carneiro';
  static const String _repoName = 'Manga_Manager';

  static String get gitApiUrl =>
      'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';

  /// Consulta a versão do app e compara com as Releases do GitHub
  static Future<void> checkUpdate(
    BuildContext context, {
    bool verbose = false,
  }) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final response = await http.get(
        Uri.parse(gitApiUrl),
        headers: {'Accept': 'application/vnd.github+json'},
      );

      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final String latestTag = (data['tag_name'] as String)
          .replaceAll('v', '')
          .trim();
      final List<dynamic> assets = data['assets'] ?? [];

      if (_isNewerVersion(currentVersion, latestTag)) {
        final downloadUrl = _getAssetUrlForPlatform(assets);
        if (context.mounted && downloadUrl != null) {
          _showUpdateDialog(
            context,
            currentVersion: currentVersion,
            newVersion: latestTag,
            downloadUrl: downloadUrl,
            releaseNotes: data['body'] ?? '',
          );
        }
      } else if (verbose && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Você já está com a versão mais recente!'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao verificar atualizações: $e');
    }
  }

  static bool _isNewerVersion(String current, String latest) {
    final c = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final l = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < l.length; i++) {
      final currentPart = i < c.length ? c[i] : 0;
      if (l[i] > currentPart) return true;
      if (l[i] < currentPart) return false;
    }
    return false;
  }

  static String? _getAssetUrlForPlatform(List<dynamic> assets) {
    if (kIsWeb) return null;

    String targetExtension = '';
    if (Platform.isAndroid) {
      targetExtension = '.apk';
    } else if (Platform.isWindows) {
      targetExtension = '.exe';
    } else if (Platform.isLinux) {
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

  static void _showUpdateDialog(
    BuildContext context, {
    required String currentVersion,
    required String newVersion,
    required String downloadUrl,
    required String releaseNotes,
  }) {
    final theme = Theme.of(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Nova Versão Disponível! (v$newVersion)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sua versão atual: v$currentVersion'),
            const SizedBox(height: 12),
            if (releaseNotes.isNotEmpty) ...[
              const Text(
                'Novidades:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(
                  child: Text(
                    releaseNotes,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Agora não'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              baixarEInstalar(context, downloadUrl);
            },
            child: const Text('Atualizar Automaticamente'),
          ),
        ],
      ),
    );
  }

  static String _escapePowerShell(String value) => value.replaceAll("'", "''");

  /// Inicia um executável elevado. O Windows mostra o UAC para o usuário aceitar.
  static Future<bool> _iniciarComElevacao(
    String exePath, {
    List<String> args = const [],
  }) async {
    final escapedPath = _escapePowerShell(exePath);
    final argumentList = args.isEmpty
        ? ''
        : " -ArgumentList '${args.map(_escapePowerShell).join("','")}'";

    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-WindowStyle',
      'Hidden',
      '-Command',
      'try { Start-Process -FilePath \'$escapedPath\'$argumentList -Verb RunAs; exit 0 } catch { exit 1 }',
    ]);

    return result.exitCode == 0;
  }

  static Future<bool> _reabrirAppComoAdministrador() async {
    final exeAtual = Platform.resolvedExecutable;
    final ok = await _iniciarComElevacao(exeAtual);
    if (ok) {
      exit(0);
    }
    return false;
  }

  static Future<void> baixarEInstalar(
    BuildContext context,
    String downloadUrl,
  ) async {
    final status = ValueNotifier<String>(
      'Baixando e aplicando atualização em segundo plano...',
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        content: ValueListenableBuilder<String>(
          valueListenable: status,
          builder: (_, mensagem, _) => Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(mensagem)),
            ],
          ),
        ),
      ),
    );

    try {
      final tempDir = await getTemporaryDirectory();
      if (!context.mounted) return;

      final filePath = p.join(tempDir.path, 'manga_manager_update.exe');
      final response = await http.get(Uri.parse(downloadUrl));
      if (!context.mounted) return;

      if (response.statusCode != 200) {
        Navigator.pop(context);
        status.dispose();
        _mostrarErroDialog(context, 'Falha ao baixar o arquivo de atualização.');
        return;
      }

      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);
      if (!context.mounted) return;

      if (!kIsWeb && Platform.isWindows) {
        status.value =
            'Aguardando permissão de administrador. Aceite o aviso do Windows...';

        final elevado = await _iniciarComElevacao(filePath, args: ['/S']);
        if (!context.mounted) return;

        if (elevado) {
          exit(0);
        }

        Navigator.pop(context);
        status.dispose();
        _mostrarDialogoPermissaoAdmin(context, filePath);
        return;
      }

      Navigator.pop(context);
      status.dispose();
      final uri = Uri.parse(downloadUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context);
      status.dispose();
      _mostrarErroDialog(context, 'Erro ao executar a atualização: $e');
    }
  }

  static void _mostrarDialogoPermissaoAdmin(
    BuildContext context,
    String instaladorPath,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Permissão de administrador'),
        content: const Text(
          'O instalador precisa de permissão de administrador. '
          'Se o aviso do Windows foi cancelado, aceite-o na próxima tentativa '
          'ou reabra o Manga Manager como administrador e atualize de novo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              final ok = await _reabrirAppComoAdministrador();
              if (!ok && context.mounted) {
                _mostrarErroDialog(
                  context,
                  'A permissão foi recusada. Abra o app pelo menu de contexto: '
                  '"Executar como administrador".',
                );
              }
            },
            child: const Text('Reabrir como administrador'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => const AlertDialog(
                  content: Row(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(width: 20),
                      Expanded(
                        child: Text(
                          'Aguardando permissão de administrador...',
                        ),
                      ),
                    ],
                  ),
                ),
              );
              final elevado = await _iniciarComElevacao(
                instaladorPath,
                args: ['/S'],
              );
              if (!context.mounted) return;
              if (elevado) {
                exit(0);
              }
              Navigator.pop(context);
              _mostrarDialogoPermissaoAdmin(context, instaladorPath);
            },
            child: const Text('Tentar de novo'),
          ),
        ],
      ),
    );
  }

  static void _mostrarErroDialog(BuildContext context, String mensagem) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Erro na Atualização'),
        content: Text(mensagem),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
