import 'dart:convert';
import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../services/update_service.dart';

class VersionUpdaterButton extends StatefulWidget {
  const VersionUpdaterButton({super.key});

  @override
  State<VersionUpdaterButton> createState() => _VersionUpdaterButtonState();
}

class _VersionUpdaterButtonState extends State<VersionUpdaterButton> {
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

  Future<void> _baixarEAtualizarAutomaticamente(
    BuildContext dialogContext,
  ) async {
    if (_downloadUrl == null) return;
    Navigator.pop(dialogContext); // Fecha o dialog
    await UpdateService.baixarEInstalar(
      context,
      _downloadUrl!,
    ); // Usa o context do Widget
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
                onPressed: () =>
                    _baixarEAtualizarAutomaticamente(dialogContext),
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

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: _checkingUpdate
            ? Colors.grey
            : (_hasUpdate ? Colors.red : Colors.green),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
              _hasUpdate ? Icons.system_update : Icons.check_circle,
              size: 16,
            ),
      label: Text('v$_installedVersion'),
      onPressed: () => _mostrarDialogoVersao(context),
    );
  }
}
