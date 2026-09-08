import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
  static const String _repoOwner = 'Daniel-S-Carneiro';
  static const String _repoName = 'Manga_Manager';

  /// Consulta a versão do app e compara com as Releases do GitHub
  static Future<void> checkUpdate(
    BuildContext context, {
    bool verbose = false,
  }) async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final url = Uri.parse(
        'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest',
      );
      final response = await http.get(
        url,
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

  /// Compara versões semânticas (ex: 1.0.0 contra 1.0.1)
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

  /// Filtra o executável/pacote correto de acordo com o sistema operacional
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
            onPressed: () async {
              Navigator.pop(ctx);
              final uri = Uri.parse(downloadUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: const Text('Baixar Atualização'),
          ),
        ],
      ),
    );
  }
}
