import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../database/db_helper.dart';
import '../widgets/atualizacao_dialog.dart';

class UpdateService {
  /// Versão com que o app abriu da última vez (para avisar que atualizou).
  static const String kVersaoApp = 'versao_app';

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

      if (context.mounted) await _avisarSeAtualizou(context, currentVersion);
      await _apagarInstaladorBaixado();
      if (!context.mounted) return;

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

  /// O app reabre sozinho depois da atualização: confirma que deu certo.
  static Future<void> _avisarSeAtualizou(
    BuildContext context,
    String versaoAtual,
  ) async {
    try {
      final db = DbHelper();
      final anterior = await db.getConfig(kVersaoApp);
      if (anterior == versaoAtual) return;
      await db.setConfig(kVersaoApp, versaoAtual);
      if (anterior != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Manga Manager atualizado para a v$versaoAtual.'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao conferir a versão anterior: $e');
    }
  }

  /// O instalador baixado fica na pasta temporária até a próxima abertura
  /// (enquanto instala, ele mesmo está em uso).
  static Future<void> _apagarInstaladorBaixado() async {
    if (kIsWeb || !Platform.isWindows) return;
    try {
      final tempDir = await getTemporaryDirectory();
      final arquivo = File(
        p.join(tempDir.path, AtualizacaoDialog.nomeInstalador),
      );
      if (await arquivo.exists()) await arquivo.delete();
    } catch (_) {
      // Ainda em uso pelo instalador: fica para a próxima
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
              baixarEInstalar(
                context,
                downloadUrl,
                versaoAtual: currentVersion,
                novaVersao: newVersion,
              );
            },
            child: const Text('Atualizar Automaticamente'),
          ),
        ],
      ),
    );
  }

  static String _escapePowerShell(String value) => value.replaceAll("'", "''");

  /// Inicia um executável elevado. O Windows mostra o UAC para o usuário aceitar.
  static Future<bool> iniciarComElevacao(
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

  /// Atualiza para a versão do [downloadUrl]. No Windows mostra a tela de
  /// atualização ([AtualizacaoDialog]): baixa com progresso, pede a permissão
  /// de administrador e o instalador reabre o app no fim. Nos outros sistemas
  /// o arquivo (APK ou .tar.gz) abre no navegador.
  static Future<void> baixarEInstalar(
    BuildContext context,
    String downloadUrl, {
    required String versaoAtual,
    required String novaVersao,
  }) async {
    if (kIsWeb || !Platform.isWindows) {
      final uri = Uri.parse(downloadUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AtualizacaoDialog(
        versaoAtual: versaoAtual,
        novaVersao: novaVersao,
        urlDownload: downloadUrl,
        iniciarElevado: (exe, args) => iniciarComElevacao(exe, args: args),
        pastaTemporaria: getTemporaryDirectory,
        encerrarApp: () => exit(0),
      ),
    );
  }
}
